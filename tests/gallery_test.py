import contextlib
import hashlib
import io
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest import mock

from helper_test import HELPER, ROOT, run
from gallery_images import fetch, normalize, public_addresses


class GalleryTests(unittest.TestCase):
    def test_public_https_pinning_and_redirect_limits(self):
        for addresses in (b"127.0.0.1 STREAM x", b"10.0.0.1 STREAM x", b"::1 STREAM x",
                          b"169.254.169.254 STREAM x", b"93.184.216.34 STREAM x\n192.168.1.1 STREAM x", b""):
            with self.assertRaises(ValueError): public_addresses(addresses)
        calls = []
        def run(argv, *args, **kwargs):
            calls.append(argv)
            if argv[0] == "getent": return b"93.184.216.34 STREAM example.org", False, 0
            Path(argv[argv.index("--output") + 1]).write_bytes(b"image")
            return b"200", False, 0
        with mock.patch("gallery_images.normalize", return_value=b"decoded"):
            self.assertEqual(fetch("https://example.org/photo.jpg", run), b"decoded")
        curl = calls[-1]
        self.assertEqual(curl[curl.index("--resolve") + 1], "example.org:443:93.184.216.34")
        self.assertIn("--max-filesize", curl)
        self.assertNotIn("--location", curl)
        self.assertEqual(curl[:2], ["curl", "-q"])
        for url in ("http://example.org/image", "file:///etc/passwd", "https://user:pass@example.org/x", "https://example.org:8080/x"):
            with self.assertRaises(ValueError): fetch(url, run)
        with mock.patch("gallery_images.normalize") as decode:
            with self.assertRaises(ValueError): fetch("https://example.org/photo.jpg", lambda *a, **k: (b"302", False, 0) if a[0][0] == "curl" else (b"93.184.216.34 STREAM x", False, 0))
            decode.assert_not_called()

    def test_native_decoder_and_oversized_inputs(self):
        with tempfile.TemporaryDirectory() as directory:
            original, output = str(Path(directory) / "input.png"), str(Path(directory) / "output.jpg")
            _, truncated, status = HELPER.run_bounded(["magick", "-size", "3200x2000", "gradient:#234b68-#9be4ef", original], 128, 4, want_status=True)
            self.assertEqual((truncated, status), (False, 0))
            self.assertTrue(normalize(original, output, HELPER.run_bounded).startswith(b"\xff\xd8\xff"))
            # Ordinary 24 MP photos used to be rejected. Preserve portrait and landscape aspect ratios.
            for dimensions, expected in (("4000x6000", b"960 1440"), ("6000x4000", b"2160 1440")):
                photo = str(Path(directory) / "photo.jpg")
                _, truncated, status = HELPER.run_bounded(["magick", "-size", dimensions, "xc:#234b68", photo], 128, 4, want_status=True)
                self.assertEqual((truncated, status), (False, 0))
                normalize(photo, output, HELPER.run_bounded)
                raw, truncated, status = HELPER.run_bounded(["magick", "identify", "-format", "%w %h", output], 128, 4, want_status=True)
                self.assertEqual((raw, truncated, status), (expected, False, 0))
            with self.assertRaises(ValueError): normalize(original, output, lambda *a, **k: (b"8192 8192", False, 0))
            with self.assertRaises(ValueError): normalize(original, output, lambda *a, **k: (b"12001 100", False, 0))
            Path(original).write_text("<svg>not a JPEG or PNG</svg>")
            with self.assertRaises(ValueError): normalize(original, output, HELPER.run_bounded)

    def test_validation_cache_save_and_explicit_apply(self):
        image = {"title": "Mountain", "description": "Example", "credit": "Example photographer",
                 "imageUrl": "https://example.org/photo.jpg", "sourceUrl": "https://example.org/license",
                 "id": "spoof", "previewUrl": "file:///etc/passwd"}
        card = {"type": "gallery", "title": "Wallpapers", "note": "Example", "images": [image]}
        validate = HELPER.ARTIFACT_VALIDATORS["gallery"]
        self.assertNotIn("id", validate(card)["images"][0])
        for count in (1, 2, 6, 8):
            self.assertEqual(len(validate({**card, "images": [image] * count})["images"]), count)
        schema = json.loads((ROOT / "resources/ai-result.schema.json").read_text())
        gallery = next(variant for variant in schema["properties"]["artifacts"]["items"]["anyOf"]
                       if variant["properties"]["type"]["enum"] == ["gallery"])
        self.assertEqual(gallery["properties"]["images"]["maxItems"], 8)
        for bad in ({**card, "images": []}, {**card, "images": [image] * 9},
                    {**card, "images": [{**image, "sourceUrl": ""}]}, {**card, "images": [{**image, "imageUrl": "file:///etc/passwd"}]}):
            with self.assertRaises(ValueError): validate(bad)
        with tempfile.TemporaryDirectory() as directory, mock.patch.dict(os.environ, HOME=directory):
            data = b"\xff\xd8\xffnormalized image fixture"
            with mock.patch.object(HELPER, "fetch_gallery_image", return_value=data), mock.patch.object(HELPER, "run_bounded") as run:
                result = HELPER.local_gallery(validate(card))
                run.assert_not_called() # Preview creation never applies or saves to Pictures.
            identity = hashlib.sha256(data).hexdigest()
            self.assertEqual(result["images"][0]["id"], identity)
            self.assertFalse((Path(directory) / "Pictures").exists())
            def action(kind):
                output = io.StringIO()
                with contextlib.redirect_stdout(output): HELPER.cmd_gallery([kind, identity])
                return json.loads(output.getvalue())
            with mock.patch.object(HELPER, "run_bounded", return_value=(b"", False, 0)) as run:
                saved = action("save")
                self.assertEqual(Path(saved["path"]).read_bytes(), data)
                run.assert_not_called()
                action("apply")
                self.assertEqual(run.call_args.args[0], ["omarchy", "theme", "bg", "set", saved["path"]])
            Path(saved["path"]).write_text("user changed this file")
            with self.assertRaises(HELPER.Denied): action("save")
            Path(saved["path"]).unlink()
            victim = Path(directory) / "victim"; victim.write_text("untouched")
            Path(saved["path"]).symlink_to(victim)
            with self.assertRaises(HELPER.Denied): action("apply")
            self.assertEqual(victim.read_text(), "untouched")
            for args in (["apply", "../../etc/passwd"], ["run", identity]):
                with self.assertRaises(HELPER.Denied): HELPER.cmd_gallery(args)
            with mock.patch.object(HELPER, "fetch_gallery_image", side_effect=ValueError("Unavailable")):
                self.assertEqual(HELPER.local_gallery(validate(card))["images"][0]["error"], "Unavailable")

    def test_gallery_count_instructions_reach_both_providers(self):
        for provider in ("codex", "claude"):
            for question in (b"show me pictures of Luffy", b"show me 3 pictures of Luffy"):
                prompts = []
                result = {"kind": "answer", "text": "No verified results available.", "commands": []}
                def fake_run(argv, cap, deadline, prompt, **kwargs):
                    prompts.append(prompt.decode())
                    event = ({"type": "result", "structured_output": result} if provider == "claude" else
                             {"type": "item.completed", "item": {"type": "agent_message", "text": json.dumps(result)}})
                    kwargs["on_line"](json.dumps(event).encode())
                    return b"", False, 0
                with mock.patch.object(HELPER.shutil, "which", return_value="/usr/bin/agent"), \
                     mock.patch.object(HELPER, "run_bounded", side_effect=fake_run):
                    run(HELPER.cmd_ai, [provider, "", "", "true"], question)
                self.assertIn("six distinct images by default", prompts[0])
                self.assertIn("respect the user's explicit image count up to eight", prompts[0])
                self.assertIn(question.decode(), prompts[0])


if __name__ == "__main__":
    unittest.main()
