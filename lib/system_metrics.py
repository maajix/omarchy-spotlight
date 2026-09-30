"""Small, bounded local snapshots for the dashboard card; never AI measurements."""
import os
import re
import time
from datetime import datetime, timezone


def cpu_ticks():
    with open("/proc/stat", "rb") as stream:
        fields = stream.readline(4096).split()
    if fields[0] != b"cpu" or len(fields) < 9:
        raise ValueError("invalid CPU counters")
    values = [int(value) for value in fields[1:9]] # Guest ticks are already in user/nice.
    return sum(values), values[3] + values[4]


def memory():
    with open("/proc/meminfo", "rb") as stream:
        raw = stream.read(65537)
    if len(raw) > 65536:
        raise ValueError("memory data exceeded its limit")
    values = {}
    for line in raw.splitlines():
        fields = line.split()
        if fields[0] in (b"MemTotal:", b"MemAvailable:"):
            if len(fields) != 3 or fields[2] != b"kB":
                raise ValueError("invalid memory data")
            values[fields[0]] = int(fields[1]) * 1024
    total, available = values[b"MemTotal:"], values[b"MemAvailable:"]
    if not 0 <= available <= total or total <= 0:
        raise ValueError("invalid memory data")
    return {"total": total, "used": total - available, "available": available}


def folder_sizes(raw, home):
    rows = []
    for line in raw.decode("utf-8", "replace").splitlines():
        parts = line.split("\t", 1)
        if len(parts) != 2 or not parts[0].isdigit():
            continue
        path = parts[1]
        name = os.path.relpath(path, home)
        # Accept only complete, direct child names; du never follows symlinks.
        if name in (".", "..") or "/" in name or len(name) > 80 or any(ord(char) < 32 for char in name):
            continue
        size = int(parts[0])
        if 0 <= size <= 1e15:
            rows.append({"name": name, "bytes": size})
    return sorted(rows, key=lambda row: (-row["bytes"], row["name"]))[:6]


def snapshot(focus, run, home, services=None):
    data = {"cpu": None, "memory": None, "disks": [], "folders": [],
            "foldersPartial": False, "services": [], "errors": []}
    if focus in ("all", "cpu"):
        try:
            total, idle = cpu_ticks()
            time.sleep(.2)
            next_total, next_idle = cpu_ticks()
            elapsed, idle_delta = next_total - total, next_idle - idle
            if elapsed <= 0 or not 0 <= idle_delta <= elapsed:
                raise ValueError("invalid CPU interval")
            data["cpu"] = {"percent": round(100 * (elapsed - idle_delta) / elapsed, 1), "cores": os.cpu_count() or 1}
        except (OSError, ValueError, IndexError):
            data["errors"].append("CPU usage unavailable")
    if focus in ("all", "memory"):
        try:
            data["memory"] = memory()
        except (OSError, ValueError, KeyError, IndexError):
            data["errors"].append("Memory usage unavailable")
    if focus in ("all", "storage"):
        seen = set()
        for label, path in (("System", "/"), ("Home", home)):
            if not path:
                continue
            try:
                stats = os.statvfs(path)
                # Btrfs subvolumes can have different f_fsid values while sharing
                # one storage pool. findmnt's filesystem UUID identifies that pool.
                raw_id, truncated_id, id_status = run(["findmnt", "--noheadings", "--output", "UUID", "--target", path],
                                                       256, 1, want_status=True)
                uuid = raw_id.decode("ascii", "replace").strip()
                identity = uuid if not truncated_id and id_status == 0 and re.fullmatch(r"[a-fA-F0-9-]{4,80}", uuid) else stats.f_fsid
                if identity in seen:
                    continue
                seen.add(identity)
                total = stats.f_blocks * stats.f_frsize
                used = (stats.f_blocks - stats.f_bfree) * stats.f_frsize
                available = stats.f_bavail * stats.f_frsize
                if total <= 0 or not 0 <= used <= total or not 0 <= available <= total:
                    raise ValueError("invalid storage statistics")
                data["disks"].append({"label": label, "total": total, "used": used, "available": available})
            except (OSError, ValueError):
                data["errors"].append(label + " storage unavailable")
        if home:
            # ponytail: bounded du snapshot, not a recursive inventory. A deadline
            # can leave a partial list; use a cached scanner if a full inventory is needed.
            raw, truncated, status = run(["du", "--block-size=1", "--max-depth=1", "--one-file-system", "--no-dereference", "--", home],
                                         65536, 3, want_status=True)
            if truncated and not raw.endswith(b"\n"):
                raw = raw.rsplit(b"\n", 1)[0] if b"\n" in raw else b""
            data["folders"] = folder_sizes(raw, home)
            data["foldersPartial"] = truncated or status != 0
            if not data["folders"]:
                data["errors"].append("Home folder sizes unavailable")
    if focus in ("all", "services"):
        if services is None:
            data["errors"].append("Service status unavailable")
        else:
            for scope in ("system", "user"):
                if scope not in services["scopes"]:
                    data["errors"].append(scope.capitalize() + " service status unavailable")
                    continue
                rows = [row for row in services["services"] if row["scope"] == scope]
                failed = [row["name"] for row in rows if row["active"] == "failed"]
                data["services"].append({"scope": scope, "active": sum(row["active"] == "active" for row in rows),
                                         "failed": len(failed), "failedNames": failed[:4], "partial": services["partial"]})
    data["retrievedAt"] = datetime.now(timezone.utc).isoformat(timespec="seconds")
    return data
