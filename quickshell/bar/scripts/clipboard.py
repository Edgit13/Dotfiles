#!/usr/bin/env python3
"""clipboard.py — історія буфера обміну для ClipboardSurface.

    clipboard.py entries [--limit N] [--thumbs N]

Читає `cliphist list`, розбирає кожен запис і друкує один JSON-рядок:

    {"ev": "entries", "items": [...]}

Поля елемента:
    id      id у cliphist
    kind    text | image | files | color | url | binary
    title   короткий підпис (перший рядок, назва файлу, розміри)
    body    другий рядок тексту (або "")
    color   "#rrggbb" для kind=color
    files   назви файлів (до 8) для kind=files
    count   скільки файлів
    w, h    розміри картинки
    bytes   розмір картинки в байтах
    fmt     формат картинки (png, jpeg, …)
    thumb   шлях до декодованого прев'ю (картинки)
    lines   скільки рядків у тексті (-1 — не декодували)
    chars   скільки символів у тексті

Картинки декодуються у ~/.cache/edots/clipvis/<id>.img (id у cliphist
незмінний, тож кеш валідний; старі файли прибираються). Повний текст
декодується лише для перших записів — решта живе на прев'ю з cliphist,
щоб відкриття було швидким.
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import time
import urllib.parse

CACHE = os.path.join(
    os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache"),
    "edots", "clipvis",
)
MAX_CACHE_FILES = 120

BIN_RE = re.compile(r"^\[\[\s*binary data\b(.*)\]\]$", re.I)
SIZE_RE = re.compile(r"(\d+(?:\.\d+)?)\s*(B|KB|KiB|MB|MiB|GB|GiB)\b", re.I)
DIM_RE = re.compile(r"\b(\d{2,5})x(\d{2,5})\b")
FMT_RE = re.compile(r"\b(png|jpe?g|webp|gif|bmp|tiff?|svg|heic|heif|avif)\b", re.I)
COLOR_RE = re.compile(r"^#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$")
URL_RE = re.compile(r"^[a-z][a-z0-9+.-]*://\S+$", re.I)

UNITS = {
    "b": 1, "kb": 1000, "kib": 1024,
    "mb": 1000 ** 2, "mib": 1024 ** 2,
    "gb": 1000 ** 3, "gib": 1024 ** 3,
}

TEXT_DECODE = 24        # стільки перших текстових записів декодуємо повністю
TEXT_CAP = 8192         # байт на текст
DECODE_TIMEOUT = 5


def run(cmd, data=None, timeout=DECODE_TIMEOUT):
    try:
        p = subprocess.run(cmd, input=data, stdout=subprocess.PIPE,
                           stderr=subprocess.DEVNULL, timeout=timeout)
        return p.returncode, p.stdout
    except (OSError, subprocess.TimeoutExpired):
        return 1, b""


def decode(ident, preview):
    return run(["cliphist", "decode"], f"{ident}\t{preview}".encode())[1]


def clean(text: str, limit: int) -> str:
    line = " ".join(text.split())
    return line if len(line) <= limit else line[: limit - 1].rstrip() + "…"


def image_info(preview: str) -> dict:
    tail = BIN_RE.match(preview)
    info = {"bytes": 0, "fmt": "", "w": 0, "h": 0}
    if not tail:
        return info
    body = tail.group(1)
    m = SIZE_RE.search(body)
    if m:
        info["bytes"] = int(float(m.group(1)) * UNITS[m.group(2).lower()])
    m = DIM_RE.search(body)
    if m:
        info["w"], info["h"] = int(m.group(1)), int(m.group(2))
    m = FMT_RE.search(body)
    if m:
        info["fmt"] = "jpg" if m.group(1).lower() in ("jpeg", "jpg") else m.group(1).lower()
    return info


def thumb(ident: str, data: bytes) -> str:
    if not data:
        return ""
    os.makedirs(CACHE, exist_ok=True)
    path = os.path.join(CACHE, f"{ident}.img")
    try:
        if not (os.path.exists(path) and os.path.getsize(path) > 0):
            tmp = path + ".tmp"
            with open(tmp, "wb") as f:
                f.write(data)
            os.replace(tmp, path)
    except OSError:
        return ""
    return path


def prune(keep: set[str]) -> None:
    try:
        names = os.listdir(CACHE)
    except OSError:
        return
    files = []
    for name in names:
        if not name.endswith(".img"):
            continue
        if name[:-4] not in keep:
            try:
                os.unlink(os.path.join(CACHE, name))
            except OSError:
                pass
        else:
            files.append(name)
    if len(files) <= MAX_CACHE_FILES:
        return
    files.sort(key=lambda n: os.path.getmtime(os.path.join(CACHE, n)))
    for name in files[: len(files) - MAX_CACHE_FILES]:
        try:
            os.unlink(os.path.join(CACHE, name))
        except OSError:
            pass


FILE_RE = re.compile(r"file://\S+")

def file_names(text: str) -> list[str]:
    """Назви файлів, якщо в тексті лише URI (по одному на рядок або через пробіл)."""
    uris = FILE_RE.findall(text)
    if not uris or FILE_RE.sub("", text).strip():
        return []
    names = []
    for uri in uris:
        path = urllib.parse.unquote(urllib.parse.urlparse(uri).path)
        name = os.path.basename(path.rstrip("/")) or path
        names.append(name)
    return names


def classify(ident: str, preview: str, decode_text: bool) -> dict:
    item = {
        "id": ident, "kind": "text", "title": clean(preview, 190), "body": "",
        "preview": preview,
        "color": "", "files": [], "count": 0, "w": 0, "h": 0, "bytes": 0,
        "fmt": "", "thumb": "", "lines": -1, "chars": -1,
    }

    if BIN_RE.match(preview):
        info = image_info(preview)
        item.update(info)
        if info["fmt"] or info["w"]:
            item["kind"] = "image"
            item["title"] = (f'{info["w"]}×{info["h"]}' if info["w"] and info["h"]
                             else (info["fmt"].upper() or "image"))
            item["body"] = info["fmt"].upper() if info["w"] and info["h"] else ""
            return item
        item["kind"] = "binary"
        return item

    # текст: повний вміст потрібен для списків файлів і багаторядкових прев'ю
    needs_full = decode_text or preview.startswith("file://")
    text = preview
    if needs_full:
        raw = decode(ident, preview)
        if raw:
            try:
                text = raw.decode("utf-8")
            except UnicodeDecodeError:
                text = raw.decode("utf-8", "replace")
            if "\x00" in text:
                item["kind"] = "binary"
                text = preview

    stripped = text.strip()
    lines = [ln.strip() for ln in stripped.splitlines() if ln.strip()]
    names = file_names(stripped)

    if names:
        item["kind"] = "files"
        item["files"] = names[:8]
        item["count"] = len(names)
        item["title"] = names[0]
        item["body"] = ", ".join(names[1:3])
    elif COLOR_RE.match(stripped):
        item["kind"] = "color"
        item["color"] = stripped.lower()
        item["title"] = stripped.lower()
    elif URL_RE.match(stripped):
        item["kind"] = "url"
        host = urllib.parse.urlparse(stripped).netloc
        item["title"] = host or clean(stripped, 60)
        item["body"] = clean(stripped, 190)
    else:
        item["title"] = clean(lines[0], 190) if lines else ""
        item["body"] = clean(lines[1], 190) if len(lines) > 1 else ""
        item["lines"] = len(lines)
        item["chars"] = len(stripped)

    return item


def main(argv):
    cmd = argv[1] if len(argv) > 1 else "entries"
    if cmd not in ("entries", "list"):
        print(__doc__, file=sys.stderr)
        return 2

    limit = 200
    thumbs = 48
    for i, arg in enumerate(argv):
        if arg == "--limit" and i + 1 < len(argv):
            limit = max(1, int(argv[i + 1]))
        elif arg == "--thumbs" and i + 1 < len(argv):
            thumbs = max(0, int(argv[i + 1]))

    rc, out = run(["cliphist", "list"], timeout=6)
    if rc != 0:
        print(json.dumps({"ev": "error", "text": "cliphist list failed"}))
        return 1

    # читаємо весь список: повний набір id потрібен, щоб не прибирати чужі прев'ю
    rows = []
    for line in out.decode("utf-8", "replace").splitlines():
        if "\t" not in line:
            continue
        ident, preview = line.split("\t", 1)
        rows.append((ident, preview))

    keep = {ident for ident, _ in rows}
    rows = rows[:limit]

    items = []
    texts = 0
    images = 0
    for ident, preview in rows:
        if BIN_RE.match(preview):
            if images >= thumbs:
                info = image_info(preview)
                item = classify(ident, preview, False)
                item.update(info)
                items.append(item)
                continue
            images += 1
            item = classify(ident, preview, False)
            if item["kind"] == "image":
                item["thumb"] = thumb(ident, decode(ident, preview))
            items.append(item)
        else:
            item = classify(ident, preview, texts < TEXT_DECODE)
            if texts < TEXT_DECODE:
                texts += 1
            items.append(item)

    prune(keep)
    print(json.dumps({"ev": "entries", "items": items,
                      "at": int(time.time())}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
