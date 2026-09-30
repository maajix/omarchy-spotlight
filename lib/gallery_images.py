"""Bounded public HTTPS images, decoded outside Quickshell using native tools."""
import ipaddress
import os
import tempfile
from urllib.parse import urlsplit

IMAGE_BYTES = 8 * 1024 * 1024


def public_addresses(raw):
    addresses = list(dict.fromkeys(line.split()[0] for line in raw.decode().splitlines() if line.split()))
    if not addresses or any(not ipaddress.ip_address(address).is_global for address in addresses):
        raise ValueError("Image host must resolve only to public addresses")
    return addresses


def fetch(url, run):
    parsed = urlsplit(url)
    if (parsed.scheme != "https" or not parsed.hostname or parsed.username or parsed.password
            or parsed.port not in (None, 443) or any(char.isspace() or ord(char) < 32 for char in url)):
        raise ValueError("Image URL must use public HTTPS on port 443")
    host = parsed.hostname.encode("idna").decode("ascii")
    if not all(char.isalnum() or char in ".-:" for char in host):
        raise ValueError("Invalid image host")
    raw, truncated, status = run(["getent", "ahosts", host], 4096, 2, want_status=True)
    if truncated or status != 0:
        raise ValueError("Image host lookup failed")
    address = public_addresses(raw)[0]
    pinned = "[" + address + "]" if ":" in address else address
    # No redirects, proxy or curlrc; the TLS hostname stays intact while DNS is pinned.
    with tempfile.TemporaryDirectory(prefix="spotlight-image-") as directory:
        original, normalized = os.path.join(directory, "input"), os.path.join(directory, "image.jpg")
        raw, truncated, status = run([
            "curl", "-q", "--silent", "--fail", "--noproxy", "*", "--proto", "=https",
            "--resolve", host + ":443:" + pinned, "--connect-timeout", "3", "--max-time", "8",
            "--max-filesize", str(IMAGE_BYTES), "--output", original, "--write-out", "%{http_code}", url
        ], 256, 9, want_status=True)
        if truncated or status != 0 or raw != b"200" or os.path.getsize(original) > IMAGE_BYTES:
            raise ValueError("Image download failed or exceeded its limit")
        return normalize(original, normalized, run)


def normalize(original, normalized, run):
    with open(original, "rb") as file:
        magic = file.read(8)
    codec = "PNG" if magic == b"\x89PNG\r\n\x1a\n" else "JPEG" if magic.startswith(b"\xff\xd8\xff") else ""
    if not codec:
        raise ValueError("Only PNG and JPEG images are supported")
    limits = ["-limit", "memory", "256MiB", "-limit", "map", "0", "-limit", "disk", "0",
              "-limit", "thread", "1", "-limit", "time", "3"]
    raw, truncated, status = run(["magick", "identify"] + limits + ["-ping", "-format", "%w %h", codec + ":" + original],
                                 128, 4, want_status=True)
    try:
        width, height = map(int, raw.split())
    except ValueError:
        raise ValueError("Invalid image dimensions")
    if truncated or status != 0 or not 1 <= width <= 8192 or not 1 <= height <= 8192 or width * height > 8_000_000:
        raise ValueError("Image dimensions exceed their limit")
    _, truncated, status = run(["magick"] + limits + [codec + ":" + original + "[0]", "-auto-orient",
        "-resize", "2560x1440>", "-background", "#182a40", "-alpha", "remove", "-strip", "-quality", "90",
        "JPEG:" + normalized], 128, 4, want_status=True)
    if truncated or status != 0:
        raise ValueError("Image decoding failed")
    with open(normalized, "rb") as file:
        data = file.read(IMAGE_BYTES + 1)
    if not data or len(data) > IMAGE_BYTES:
        raise ValueError("Decoded image exceeds its limit")
    return data
