"""Validate optional AI cards before their data reaches QML."""

import difflib
import hashlib
import json
import math
import re
import unicodedata
from datetime import datetime, timezone
from urllib.parse import quote, urlsplit


def unsafe(char):
    # Card text reaches copy buttons too, so it gets the guard commands[] has.
    return ord(char) < 32 or 127 <= ord(char) <= 159 or unicodedata.category(char) == "Cf"


def text(value, limit=160):
    if not isinstance(value, str) or not 1 <= len(value.strip()) <= limit:
        raise ValueError("text must contain 1–" + str(limit) + " characters")
    if any(unsafe(char) for char in value):
        raise ValueError("invalid artifact text")
    return value.strip()


def palette(item):
    colors = item.get("colors")
    if not isinstance(colors, list) or not 2 <= len(colors) <= 8:
        raise ValueError("a palette needs 2–8 colors")
    clean = []
    for color in colors:
        if not isinstance(color, dict) or not re.fullmatch(r"#[0-9a-fA-F]{6}", str(color.get("hex", ""))):
            raise ValueError("invalid palette color")
        clean.append({"label": text(color.get("label"), 40), "hex": color["hex"].upper()})
    return {"type": "palette", "title": text(item.get("title")), "colors": clean}


def number(value):
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value) or abs(value) > 1e15:
        raise ValueError("invalid artifact number")
    return value


def source(value):
    if value == "":
        return ""
    value = text(value, 2048)
    url = urlsplit(value)
    if (url.scheme != "https" or not url.hostname or url.username or url.password
            or any(char.isspace() for char in value)):
        raise ValueError("invalid artifact source")
    return value


def chart(item):
    variant, labels, series = item.get("variant"), item.get("labels"), item.get("series")
    if (variant not in ("line", "bar", "donut") or not isinstance(labels, list)
            or not 2 <= len(labels) <= (8 if variant == "donut" else 12 if variant == "bar" else 24)
            or not isinstance(series, list) or not 1 <= len(series) <= (1 if variant == "donut" else 4)):
        raise ValueError("invalid chart dimensions")
    clean = []
    for entry in series:
        if not isinstance(entry, dict) or not isinstance(entry.get("values"), list) or len(entry["values"]) != len(labels):
            raise ValueError("invalid chart series")
        values = [number(value) for value in entry["values"]]
        if variant == "donut" and (any(value < 0 for value in values) or sum(values) <= 0):
            raise ValueError("invalid donut values")
        clean.append({"label": text(entry.get("label"), 48), "values": values})
    url = source(item.get("sourceUrl"))
    unit = item.get("unit")
    if not isinstance(unit, str) or len(unit) > 20 or any(unsafe(char) for char in unit):
        raise ValueError("invalid chart unit")
    return {"type": "chart", "title": text(item.get("title")), "variant": variant,
            "labels": [text(label, 48) for label in labels], "series": clean, "unit": unit,
            "note": text(item.get("note"), 240), "sourceUrl": url,
            "retrievedAt": datetime.now(timezone.utc).isoformat(timespec="minutes") if url else ""}


def comparison(item):
    options = item.get("options")
    if not isinstance(options, list) or not 2 <= len(options) <= 4:
        raise ValueError("a comparison needs 2–4 options")
    clean = []
    for option in options:
        if not isinstance(option, dict) or type(option.get("recommended")) is not bool:
            raise ValueError("invalid comparison option")
        entry = {key: text(option.get(key), limit) for key, limit in
                 (("name", 80), ("price", 60), ("summary", 200))}
        for key in ("pros", "cons"):
            values = option.get(key)
            if not isinstance(values, list) or not 1 <= len(values) <= 4:
                raise ValueError("invalid comparison details")
            entry[key] = [text(value, 120) for value in values]
        facts = option.get("facts")
        if not isinstance(facts, list) or len(facts) > 5:
            raise ValueError("invalid comparison facts")
        entry["facts"] = [{"label": text(fact.get("label"), 40), "value": text(fact.get("value"), 100)}
                          for fact in facts if isinstance(fact, dict)]
        if len(entry["facts"]) != len(facts):
            raise ValueError("invalid comparison facts")
        entry["sourceUrl"] = source(option.get("sourceUrl"))
        entry["recommended"] = option["recommended"]
        clean.append(entry)
    if sum(option["recommended"] for option in clean) > 1:
        raise ValueError("multiple comparison recommendations")
    return {"type": "comparison", "title": text(item.get("title")),
            "note": text(item.get("note"), 240), "options": clean,
            "retrievedAt": datetime.now(timezone.utc).isoformat(timespec="minutes")
            if any(option["sourceUrl"] for option in clean) else ""}


def timeline(item):
    entries = item.get("entries")
    if not isinstance(entries, list) or not 1 <= len(entries) <= 12:
        raise ValueError("a timeline needs 1–12 entries")
    clean = []
    for entry in entries:
        if not isinstance(entry, dict) or entry.get("status") not in ("planned", "current", "done"):
            raise ValueError("invalid timeline entry")
        clean.append({"when": text(entry.get("when"), 60), "title": text(entry.get("title"), 100),
                      "description": text(entry.get("description"), 240), "status": entry["status"],
                      "sourceUrl": source(entry.get("sourceUrl"))})
    return {"type": "timeline", "title": text(item.get("title")), "note": text(item.get("note"), 240),
            "entries": clean, "retrievedAt": datetime.now(timezone.utc).isoformat(timespec="minutes")
            if any(entry["sourceUrl"] for entry in clean) else ""}


def diagram(item):
    nodes, edges = item.get("nodes"), item.get("edges")
    if (not isinstance(nodes, list) or not 2 <= len(nodes) <= 10
            or not isinstance(edges, list) or not 1 <= len(edges) <= 16):
        raise ValueError("a diagram needs 2–10 nodes and 1–16 connections")
    clean_nodes, ids, positions = [], set(), set()
    for node in nodes:
        if (not isinstance(node, dict) or not isinstance(node.get("id"), str)
                or not re.fullmatch(r"[A-Za-z0-9_-]{1,24}", node["id"])):
            raise ValueError("invalid diagram node")
        column, row = node.get("column"), node.get("row")
        if (type(column) is not int or not 0 <= column <= 2 or type(row) is not int or not 0 <= row <= 5
                or node["id"] in ids or (column, row) in positions):
            raise ValueError("diagram nodes must have unique IDs and grid positions")
        ids.add(node["id"])
        positions.add((column, row))
        clean_nodes.append({"id": node["id"], "label": text(node.get("label"), 60), "column": column, "row": row})
    clean_edges, pairs = [], set()
    for edge in edges:
        if not isinstance(edge, dict):
            raise ValueError("invalid diagram connection")
        start, end, label = edge.get("from"), edge.get("to"), edge.get("label")
        if (not isinstance(start, str) or not isinstance(end, str) or start not in ids or end not in ids
                or start == end or (start, end) in pairs):
            raise ValueError("invalid diagram connection")
        if not isinstance(label, str) or len(label) > 40 or any(unsafe(char) for char in label):
            raise ValueError("invalid diagram connection label")
        pairs.add((start, end))
        clean_edges.append({"from": start, "to": end, "label": label})
    url = source(item.get("sourceUrl"))
    return {"type": "diagram", "title": text(item.get("title")), "note": text(item.get("note"), 240),
            "nodes": clean_nodes, "edges": clean_edges, "sourceUrl": url,
            "retrievedAt": datetime.now(timezone.utc).isoformat(timespec="minutes") if url else ""}


def checklist(item):
    items = item.get("items")
    if not isinstance(items, list) or not 1 <= len(items) <= 12:
        raise ValueError("a checklist needs 1–12 tasks")
    clean = []
    for entry in items:
        if not isinstance(entry, dict):
            raise ValueError("invalid checklist task")
        clean.append({"title": text(entry.get("title"), 100),
                      "description": text(entry.get("description"), 240)})
    title = text(item.get("title"))
    # Only user actions set progress; provider fields cannot mark tasks done.
    identity = json.dumps([title, clean], ensure_ascii=False, sort_keys=True).encode()
    url = source(item.get("sourceUrl"))
    return {"type": "checklist", "id": hashlib.sha256(identity).hexdigest()[:32],
            "title": title, "note": text(item.get("note"), 240), "items": clean, "sourceUrl": url,
            "retrievedAt": datetime.now(timezone.utc).isoformat(timespec="minutes") if url else ""}


def dashboard(item):
    if item.get("focus") not in ("all", "cpu", "memory", "storage", "services"):
        raise ValueError("invalid dashboard focus")
    # Provider supplies only a selector; helper-owned measurements replace all data.
    return {"type": "dashboard", "title": text(item.get("title")), "focus": item["focus"]}


def places(item):
    entries = item.get("places")
    if not isinstance(entries, list) or not 1 <= len(entries) <= 4:
        raise ValueError("a places card needs 1–4 places")
    clean = []
    for entry in entries:
        if not isinstance(entry, dict):
            raise ValueError("invalid place")
        place = {key: text(entry.get(key), limit) for key, limit in
                 (("name", 100), ("category", 60), ("address", 180), ("hours", 160), ("summary", 180))}
        rating = entry.get("rating")
        if rating is not None and not 0 <= number(rating) <= 5:
            raise ValueError("invalid place rating")
        place["rating"] = rating
        place["ratingSource"] = text(entry.get("ratingSource"), 60) if rating is not None else ""
        place["sourceUrl"] = source(entry.get("sourceUrl"))
        place["mapUrl"] = "https://www.openstreetmap.org/search?query=" + quote(place["name"] + " " + place["address"], safe="")
        clean.append(place)
    return {"type": "places", "title": text(item.get("title")), "note": text(item.get("note"), 240),
            "places": clean, "retrievedAt": datetime.now(timezone.utc).isoformat(timespec="minutes")
            if any(place["sourceUrl"] for place in clean) else ""}


def diff(item):
    files = item.get("files")
    if not isinstance(files, list) or not 1 <= len(files) <= 3:
        raise ValueError("a diff needs 1–3 files")
    clean = []
    for entry in files:
        if not isinstance(entry, dict):
            raise ValueError("invalid diff file")
        path = text(entry.get("path"), 160) # A display label, never a filesystem path to open.
        for field in ("before", "after"):
            value = entry.get(field)
            if (not isinstance(value, str) or len(value) > 6000 or len(value.splitlines()) > 120
                    or any(len(line) > 300 for line in value.splitlines())
                    or any(unsafe(char) and char not in "\n\r\t" for char in value)):
                raise ValueError("invalid or oversized diff contents")
        before, after = entry["before"].replace("\r\n", "\n"), entry["after"].replace("\r\n", "\n")
        lines = list(difflib.unified_diff(before.splitlines(keepends=True), after.splitlines(keepends=True),
                                         fromfile="a/" + path, tofile="b/" + path, lineterm=""))
        display_lines = []
        for index, line in enumerate(lines):
            display_lines.append(line.rstrip("\n"))
            if index > 1 and line[0] in " +-" and not line.endswith("\n"):
                display_lines.append("\\ No newline at end of file")
        lines = display_lines
        rows, old, new = [], 0, 0
        for line in lines[2:]:
            if line.startswith("@@"):
                match = re.match(r"@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@", line)
                old, new = int(match[1]), int(match[2])
                rows.append({"kind": "hunk", "text": line, "old": "", "new": ""})
            elif line.startswith("\\"):
                rows.append({"kind": "meta", "text": line, "old": "", "new": ""})
            else:
                kind = "added" if line[0] == "+" else "removed" if line[0] == "-" else "context"
                rows.append({"kind": kind, "text": line[1:], "old": "" if kind == "added" else str(old),
                             "new": "" if kind == "removed" else str(new)})
                if kind != "added": old += 1
                if kind != "removed": new += 1
        clean.append({"path": path, "before": before, "after": after, "rows": rows,
                      "added": sum(row["kind"] == "added" for row in rows),
                      "removed": sum(row["kind"] == "removed" for row in rows),
                      "diff": "\n".join(lines) + ("\n" if lines else "")})
    return {"type": "diff", "title": text(item.get("title")), "note": text(item.get("note"), 240), "files": clean}


def gallery(item):
    images = item.get("images")
    if not isinstance(images, list) or not 1 <= len(images) <= 8:
        raise ValueError("a gallery needs 1–8 images")
    clean = []
    for image in images:
        if not isinstance(image, dict):
            raise ValueError("invalid gallery image")
        url, attribution = source(image.get("imageUrl")), source(image.get("sourceUrl"))
        if not url or not attribution:
            raise ValueError("images need direct HTTPS and source URLs")
        clean.append({"title": text(image.get("title"), 80), "description": text(image.get("description"), 160),
                      "credit": text(image.get("credit"), 100), "imageUrl": url, "sourceUrl": attribution})
    return {"type": "gallery", "title": text(item.get("title")), "note": text(item.get("note"), 240), "images": clean}


VALIDATORS = {"palette": palette, "chart": chart, "comparison": comparison, "timeline": timeline,
              "diagram": diagram, "checklist": checklist, "dashboard": dashboard, "places": places, "diff": diff,
              "gallery": gallery}
