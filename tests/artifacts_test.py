import contextlib
import io
import json
import unittest

from helper_test import HELPER


class ArtifactTests(unittest.TestCase):
    def test_final_wire_budget_keeps_answer_and_warns_about_expanded_diff(self):
        for char in ("a", "😀"):
            contents = (char * 49 + "\n") * 120
            card = {"type": "diff", "title": "Example", "note": "Example", "files": [
                {"path": "a.txt", "before": contents, "after": contents.replace(char, "🦊" if char == "😀" else "b")}
            ] * 3}
            response = {"kind": "answer", "text": char * HELPER.AI_TEXT_CHARS, "commands": [], "artifacts": [card, card]}
            raw = json.dumps(response, ensure_ascii=False).encode()
            self.assertLess(len(raw), HELPER.AI_OUTPUT_BYTES)
            result = HELPER.ai_result(raw, "codex")
            output = io.StringIO()
            with contextlib.redirect_stdout(output): HELPER.emit_ai_result(result)
            self.assertLessEqual(len(output.getvalue().encode("utf-16-le")) // 2, HELPER.AI_REPLY_CHARS)
            reply = json.loads(output.getvalue())
            self.assertEqual(reply["result"]["text"], response["text"])
            if char == "😀":
                self.assertLess(len(reply["result"]["artifacts"]), 2)
                self.assertIn("omitted", reply["result"]["artifactWarnings"][0])
            else:
                self.assertEqual(len(reply["result"]["artifacts"]), 2)

    def test_diff_line_numbers_and_limits(self):
        file = {"path": "example.toml", "before": "size = 12\nkeep = true\n", "after": "size = 14\nkeep = true\n"}
        card = {"type": "diff", "title": "Font size", "note": "Illustrative example", "files": [file]}
        validate = HELPER.ARTIFACT_VALIDATORS["diff"]
        result = validate(card)["files"][0]
        self.assertEqual((result["added"], result["removed"]), (1, 1))
        self.assertEqual(result["rows"][1], {"kind": "removed", "old": "1", "new": "", "text": "size = 12"})
        self.assertEqual(result["rows"][2], {"kind": "added", "old": "", "new": "1", "text": "size = 14"})
        self.assertEqual(result["rows"][3]["old"], "2")
        self.assertIn("+size = 14", result["diff"])
        newline_change = validate({**card, "files": [{**file, "before": "line\n", "after": "line"}]})["files"][0]
        self.assertEqual((newline_change["added"], newline_change["removed"]), (1, 1))
        self.assertIn("No newline at end of file", newline_change["diff"])
        self.assertEqual(validate({**card, "files": [{**file, "after": file["before"]}]})["files"][0]["rows"], [])
        self.assertEqual(validate({**card, "files": [{**file, "before": ""}]})["files"][0]["removed"], 0)
        self.assertEqual(validate({**card, "files": [{**file, "after": ""}]})["files"][0]["added"], 0)
        for bad in ({**card, "files": []}, {**card, "files": [file] * 4},
                    {**card, "files": [{**file, "before": "x" * 6001}]},
                    {**card, "files": [{**file, "before": "line\n" * 121}]},
                    {**card, "files": [{**file, "after": "\x00"}]}):
            with self.assertRaises(ValueError):
                validate(bad)

    def test_places_bound_ratings_and_build_map_links(self):
        place = {"name": "Example Ramen", "category": "Restaurant", "address": "Example Street & Park, Tokyo",
                 "hours": "Not verified", "summary": "Illustrative example", "rating": None, "ratingSource": "", "sourceUrl": ""}
        card = {"type": "places", "title": "Example places", "note": "Fictional example", "places": [place]}
        validate = HELPER.ARTIFACT_VALIDATORS["places"]
        result = validate(card)["places"][0]
        self.assertIsNone(result["rating"])
        self.assertIn("%26", result["mapUrl"])
        self.assertTrue(result["mapUrl"].startswith("https://www.openstreetmap.org/search?query="))
        for bad in ({**card, "places": []}, {**card, "places": [place] * 5},
                    {**card, "places": [{**place, "rating": True}]}, {**card, "places": [{**place, "rating": 6}]},
                    {**card, "places": [{**place, "rating": float("nan")}]},
                    {**card, "places": [{**place, "rating": 4, "ratingSource": ""}]},
                    {**card, "places": [{**place, "sourceUrl": "javascript:alert(1)"}]}):
            with self.assertRaises(ValueError):
                validate(bad)

    def test_checklist_identity_is_stable_and_progress_is_user_owned(self):
        card = {"type": "checklist", "title": "Server migration", "note": "Suggested plan", "sourceUrl": "",
                "items": [{"title": "Check backups", "description": "Try a restore."}]}
        validate = HELPER.ARTIFACT_VALIDATORS["checklist"]
        clean = validate(card)
        self.assertEqual(validate({**card, "note": "Another note"})["id"], clean["id"])
        self.assertNotEqual(validate({**card, "title": "Another plan"})["id"], clean["id"])
        self.assertNotIn("checked", validate({**card, "checked": [0]}))
        self.assertNotIn("checked", validate({**card, "items": [{**card["items"][0], "checked": True}]})["items"][0])
        for bad in ({**card, "items": []}, {**card, "items": card["items"] * 13},
                    {**card, "items": ["wrong shape"]}, {**card, "items": [{"title": "x" * 101, "description": "Test"}]},
                    {**card, "sourceUrl": "file:///etc/passwd"}):
            with self.assertRaises(ValueError):
                validate(bad)

    def test_diagrams_reject_overlaps_and_unknown_connections(self):
        nodes = [{"id": "client", "label": "Client", "column": 0, "row": 0},
                 {"id": "server", "label": "Server", "column": 0, "row": 1}]
        edge = {"from": "client", "to": "server", "label": "Request"}
        card = {"type": "diagram", "title": "Request", "note": "Conceptual example", "sourceUrl": "",
                "nodes": nodes, "edges": [edge]}
        validate = HELPER.ARTIFACT_VALIDATORS["diagram"]
        self.assertEqual(validate(card)["edges"], [edge])
        for bad in ({**card, "nodes": [nodes[0], {**nodes[1], "row": 0}]},
                    {**card, "nodes": [nodes[0], {**nodes[1], "column": 3}]},
                    {**card, "nodes": [nodes[0], {**nodes[1], "id": "client"}]},
                    {**card, "nodes": [nodes[0], {**nodes[1], "id": 12}]},
                    {**card, "edges": [{**edge, "to": "missing"}]},
                    {**card, "edges": [edge, edge]},
                    {**card, "sourceUrl": "javascript:alert(1)"}):
            with self.assertRaises(ValueError):
                validate(bad)

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
