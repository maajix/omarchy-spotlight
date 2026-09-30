"""Validate optional AI cards before their data reaches QML."""

import math
import re
from datetime import datetime, timezone
from urllib.parse import urlsplit


def text(value, limit=160):
    if not isinstance(value, str) or not 1 <= len(value.strip()) <= limit:
        raise ValueError("text must contain 1–" + str(limit) + " characters")
    if any(ord(char) < 32 for char in value):
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
    if not isinstance(unit, str) or len(unit) > 20 or any(ord(char) < 32 for char in unit):
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
        if not isinstance(label, str) or len(label) > 40 or any(ord(char) < 32 for char in label):
            raise ValueError("invalid diagram connection label")
        pairs.add((start, end))
        clean_edges.append({"from": start, "to": end, "label": label})
    url = source(item.get("sourceUrl"))
    return {"type": "diagram", "title": text(item.get("title")), "note": text(item.get("note"), 240),
            "nodes": clean_nodes, "edges": clean_edges, "sourceUrl": url,
            "retrievedAt": datetime.now(timezone.utc).isoformat(timespec="minutes") if url else ""}


VALIDATORS = {"palette": palette, "chart": chart, "comparison": comparison, "timeline": timeline,
              "diagram": diagram}
