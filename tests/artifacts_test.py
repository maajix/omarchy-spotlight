import json
import unittest

from helper_test import HELPER


class ArtifactTests(unittest.TestCase):
    def test_timeline_preserves_order_and_rejects_invalid_entries(self):
        entry = {"when": "Saturday 09:00", "title": "Breakfast", "description": "Start the day slowly.",
                 "status": "planned", "sourceUrl": ""}
        card = {"type": "timeline", "title": "Weekend", "note": "Suggested plan", "entries": [entry]}
        result = HELPER.ARTIFACT_VALIDATORS["timeline"](card)
        self.assertEqual(result["entries"][0], entry)
        for bad in ({**card, "entries": []}, {**card, "entries": [entry] * 13},
                    {**card, "entries": [{**entry, "status": "unknown"}]},
                    {**card, "entries": [{**entry, "sourceUrl": "file:///etc/passwd"}]}):
            with self.assertRaises(ValueError):
                HELPER.ARTIFACT_VALIDATORS["timeline"](bad)

    def test_palette_is_normalized_and_invalid_cards_keep_the_answer(self):
        artifact = {"type": "palette", "title": " Ocean ", "colors": [
            {"label": "Background", "hex": "#14283f"},
            {"label": "Accent", "hex": "#79d7eb"}]}
        response = {"kind": "answer", "text": "Try this palette.", "commands": [], "artifacts": [artifact]}
        result = HELPER.ai_result(json.dumps(response).encode(), "codex")
        self.assertEqual(result["artifacts"][0]["title"], "Ocean")
        self.assertEqual(result["artifacts"][0]["colors"][0]["hex"], "#14283F")
        for bad in ("red", "#123", "#12345678", "#GGGGGG", "#123456\n"):
            artifact["colors"][0]["hex"] = bad
            result = HELPER.ai_result(json.dumps(response).encode(), "codex")
            self.assertEqual(result["artifacts"], [])
            self.assertEqual(result["text"], "Try this palette.")
            self.assertIn("Palette card could not be displayed", result["artifactWarnings"][0])

    def test_charts_reject_mismatched_nonfinite_and_invalid_donut_values(self):
        artifact = {"type": "chart", "title": "Example", "variant": "bar", "unit": "GB",
                    "note": "User-provided example data", "sourceUrl": "", "labels": ["A", "B"],
                    "series": [{"label": "Usage", "values": [-2, 4]}]}
        response = {"kind": "answer", "text": "Example chart.", "commands": [], "artifacts": [artifact]}
        def result():
            return HELPER.ai_result(json.dumps(response).encode(), "codex")["artifacts"]
        self.assertEqual(result()[0]["series"][0]["values"], [-2, 4])
        for values in ([1], [1, float("nan")], [True, 1], [0, float("inf")]):
            artifact["series"][0]["values"] = values
            self.assertEqual(result(), [])
        artifact["variant"] = "donut"
        for values in ([-2, 4], [0, 0]):
            artifact["series"][0]["values"] = values
            self.assertEqual(result(), [])
        artifact["series"][0]["values"] = [2, 4]
        self.assertEqual(len(result()), 1)
        artifact["sourceUrl"] = "javascript:alert(1)"
        self.assertEqual(result(), [])

    def test_comparisons_bound_details_and_drop_unsafe_sources(self):
        option = {"name": "SCP", "price": "Not applicable", "summary": "Simple copies",
                  "pros": ["Widely installed"], "cons": ["No resume"], "facts": [],
                  "sourceUrl": "", "recommended": False}
        artifact = {"type": "comparison", "title": "Transfer tools", "note": "Conceptual comparison",
                    "options": [dict(option), dict(option, name="Rsync", recommended=True)]}
        response = {"kind": "answer", "text": "Compare these tools.", "commands": [], "artifacts": [artifact]}
        def result():
            return HELPER.ai_result(json.dumps(response).encode(), "codex")["artifacts"]
        self.assertEqual(len(result()[0]["options"]), 2)
        artifact["options"][0]["recommended"] = True
        self.assertEqual(result(), [])
        artifact["options"][0]["recommended"] = False
        artifact["options"][1]["sourceUrl"] = "file:///etc/passwd"
        self.assertEqual(result(), [])
        artifact["options"][1]["sourceUrl"] = ""
        artifact["options"][1]["facts"] = ["not an object"]
        self.assertEqual(result(), [])

    def test_schema_bounds_generated_comparison_text_to_validator_limits(self):
        from pathlib import Path
        schema = json.loads((Path(HELPER.__file__).resolve().parents[1]
                             / "resources/ai-result.schema.json").read_text())
        comparison = next(card for card in schema["properties"]["artifacts"]["items"]["anyOf"]
                          if card["properties"]["type"]["enum"] == ["comparison"])
        option = comparison["properties"]["options"]["items"]["properties"]
        self.assertEqual(option["summary"]["maxLength"], 200)
        self.assertEqual(option["pros"]["items"]["maxLength"], 120)
