#!/usr/bin/env python3
"""Edots Launcher Kit — data helpers for the advanced launcher.

Two things the QML side cannot do cheaply:

  emoji          build (and cache) an emoji index with searchable names
  files          fuzzy file search under $HOME (or an absolute path) via fd

Everything is printed as a single JSON line so the QML Process collector can
parse it without dealing with multi-line output.

The emoji cache lives in ~/.cache/quickshell/emoji-index.json and is rebuilt
only when this script changes (bump EMOJI_VERSION).
"""
from __future__ import annotations

import argparse
import json
import mimetypes
import os
import shutil
import subprocess
import sys
import unicodedata
from pathlib import Path

HOME = Path.home()
CACHE = Path(os.environ.get("XDG_CACHE_HOME") or HOME / ".cache") / "quickshell"
EMOJI_CACHE = CACHE / "emoji-index.json"
EMOJI_VERSION = 3

# Single-codepoint emoji ranges. Multi-codepoint sequences (ZWJ families,
# flags, skin tones) are intentionally skipped: searchability matters more
# than covering every variant.
EMOJI_RANGES = [
    (0x1F300, 0x1F5FF),
    (0x1F600, 0x1F64F),
    (0x1F680, 0x1F6FF),
    (0x1F700, 0x1F77F),
    (0x1F780, 0x1F7FF),
    (0x1F800, 0x1F8FF),
    (0x1F900, 0x1F9FF),
    (0x1FA00, 0x1FAFF),
    (0x2600, 0x26FF),
    (0x2700, 0x27BF),
    (0x2B00, 0x2BFF),
    (0x1F000, 0x1F02F),
    (0x1F0A0, 0x1F0FF),
    (0x1F100, 0x1F1AD),
    (0x1F200, 0x1F2FF),
]

SKIP_WORDS = (
    "VARIATION SELECTOR", "ZERO WIDTH", "COMBINING", "REGIONAL INDICATOR",
    "EMOJI MODIFIER", "TAG ",
)

# Extra search keywords for the emoji people actually look for. Keys are
# normalised (VS16 stripped) before matching.
ALIASES = {
    "😀": "grinning smile happy", "😃": "smiley happy", "😄": "smile happy",
    "😁": "grin happy", "😆": "laughing satisfied", "😅": "sweat smile",
    "😂": "joy laugh lol tears", "🤣": "rofl rolling laugh", "😊": "blush smile",
    "😇": "angel innocent", "🙂": "slight smile", "🙃": "upside down",
    "😉": "wink", "😌": "relieved calm", "😍": "heart eyes love",
    "🥰": "love hearts adore", "😘": "kiss blow", "😗": "kiss",
    "😙": "kiss smile", "😚": "kiss closed", "😋": "yum tasty",
    "😛": "tongue", "😜": "wink tongue", "🤪": "zany crazy",
    "😝": "tongue squint", "🤑": "money mouth", "🤗": "hug",
    "🤭": "hand over mouth giggle", "🫢": "gasp surprise", "🫣": "peek",
    "🤫": "shush quiet", "🤔": "think hmm", "🫡": "salute",
    "🤐": "zipper mouth", "🤨": "raised eyebrow", "😐": "neutral",
    "😑": "expressionless", "😶": "no mouth silent", "🫥": "dotted invisible",
    "😏": "smirk", "😒": "unamused", "🙄": "eye roll", "😬": "grimace",
    "🫨": "shaking", "🤥": "lying pinocchio", "😌": "relieved",
    "😔": "pensive sad", "😪": "sleepy", "🤤": "drool",
    "😴": "sleep zzz", "😷": "mask sick", "🤒": "sick thermometer",
    "🤕": "hurt bandage", "🤢": "nausea", "🤮": "vomit",
    "🤧": "sneeze", "🥵": "hot", "🥶": "cold", "🥴": "woozy",
    "😵": "dizzy", "🤯": "mind blown", "🤠": "cowboy",
    "🥳": "party celebrate", "🥸": "disguise", "😎": "cool sunglasses",
    "🤓": "nerd", "🧐": "monocle", "😕": "confused",
    "😟": "worried", "🙁": "frown", "😮": "open mouth wow",
    "😯": "hushed", "😲": "astonished", "😳": "flushed",
    "🥺": "pleading please", "😦": "frowning", "😧": "anguished",
    "😨": "fearful", "😰": "anxious", "😥": "sad relieved",
    "😢": "cry sad", "😭": "cry sob loud", "😱": "scream shock",
    "😖": "confounded", "😣": "persevere", "😞": "disappointed",
    "😓": "sweat", "😩": "weary", "😫": "tired",
    "🥱": "yawn", "😤": "triumph huff", "😡": "angry rage",
    "😠": "angry", "🤬": "swear cursing", "😈": "devil",
    "👿": "devil angry", "💀": "skull dead", "☠️": "skull crossbones",
    "💩": "poop", "🤡": "clown", "👹": "ogre", "👺": "goblin",
    "👻": "ghost", "👽": "alien", "🤖": "robot",
    "😺": "cat smile", "😸": "cat grin", "😹": "cat joy",
    "😻": "cat heart", "😼": "cat smirk", "😽": "cat kiss",
    "🙀": "cat scream", "😿": "cat cry", "😾": "cat angry",
    "👍": "thumbs up like yes ok", "👎": "thumbs down dislike no",
    "👌": "ok perfect", "🤌": "pinched fingers", "🤏": "pinch small",
    "✌️": "peace victory", "🤞": "fingers crossed luck",
    "🫰": "finger heart", "🤟": "love you", "🤘": "rock",
    "🤙": "call me", "👈": "point left", "👉": "point right",
    "👆": "point up", "👇": "point down", "☝️": "point up one",
    "✋": "hand stop", "🤚": "raised back hand", "🖐️": "hand fingers",
    "🖖": "vulcan", "👋": "wave hello hi bye", "🤝": "handshake deal",
    "🙏": "pray thanks please", "✍️": "write", "💅": "nails",
    "💪": "muscle strong", "🦾": "mechanical arm", "🫶": "heart hands",
    "👏": "clap applause", "🙌": "hooray raised hands", "👐": "open hands",
    "🤲": "palms up", "🤜": "fist right", "🤛": "fist left",
    "✊": "fist", "👊": "punch", "🫷": "push left", "🫸": "push right",
    "❤️": "heart love red", "🧡": "orange heart", "💛": "yellow heart",
    "💚": "green heart", "💙": "blue heart", "💜": "purple heart",
    "🖤": "black heart", "🤍": "white heart", "🤎": "brown heart",
    "💔": "broken heart", "❣️": "heart exclamation", "💕": "two hearts",
    "💞": "revolving hearts", "💓": "beating heart", "💗": "growing heart",
    "💖": "sparkling heart", "💘": "heart arrow", "💝": "heart gift",
    "💟": "heart decoration", "♥️": "heart suit", "💯": "hundred 100 perfect",
    "🔥": "fire hot lit", "✨": "sparkles stars", "⭐": "star",
    "🌟": "glowing star", "💫": "dizzy star", "⚡": "lightning zap",
    "☀️": "sun", "🌙": "moon night", "🌈": "rainbow",
    "☁️": "cloud", "🌧️": "rain", "❄️": "snow", "⛄": "snowman",
    "🌊": "wave water", "🌍": "earth globe", "🌎": "earth america",
    "🌏": "earth asia", "🌕": "full moon", "🌑": "new moon",
    "🚀": "rocket launch space", "✈️": "plane flight", "🚗": "car",
    "🚕": "taxi", "🚲": "bike bicycle", "🏠": "home house",
    "🏢": "office building", "💻": "laptop computer", "🖥️": "desktop computer",
    "⌨️": "keyboard", "🖱️": "mouse", "📱": "phone mobile",
    "⌚": "watch", "🎧": "headphones", "🎮": "game controller",
    "🕹️": "joystick", "📷": "camera", "📸": "camera flash",
    "🎥": "movie camera", "📺": "tv television", "🔊": "speaker sound",
    "🔇": "mute", "🎵": "music note", "🎶": "music notes",
    "🎤": "microphone", "🎸": "guitar", "🎹": "piano", "🥁": "drum",
    "🎉": "party tada celebrate", "🎊": "confetti", "🎁": "gift present",
    "🎂": "cake birthday", "🍰": "cake slice", "☕": "coffee",
    "🍵": "tea", "🍺": "beer", "🍻": "beers cheers", "🍷": "wine",
    "🍕": "pizza", "🍔": "burger", "🍟": "fries", "🌮": "taco",
    "🍣": "sushi", "🍎": "apple", "🍌": "banana", "🍓": "strawberry",
    "🍫": "chocolate", "🍿": "popcorn", "🍩": "donut", "🥑": "avocado",
    "✅": "check done yes", "❌": "cross no wrong", "⚠️": "warning",
    "❗": "exclamation", "❓": "question", "💡": "idea bulb",
    "🔔": "bell notification", "🔒": "lock", "🔓": "unlock",
    "🔑": "key", "🔍": "search magnify", "📌": "pin",
    "📎": "paperclip attach", "✏️": "pencil edit", "📝": "memo note edit",
    "📄": "document page", "📁": "folder", "📂": "folder open",
    "🗑️": "trash delete", "⚙️": "gear settings", "🔧": "wrench tool",
    "🔨": "hammer", "🛠️": "tools", "🧪": "test tube", "🧬": "dna",
    "🔬": "microscope", "💊": "pill", "💉": "syringe", "🩺": "stethoscope",
    "🚑": "ambulance", "🚨": "siren", "🛑": "stop sign",
    "🚧": "construction", "🏁": "flag finish", "🚩": "flag",
    "🎯": "target goal", "🏆": "trophy win", "🥇": "gold medal",
    "🥈": "silver medal", "🥉": "bronze medal", "💰": "money bag",
    "💸": "money wings", "💳": "credit card", "🪙": "coin",
    "📈": "chart up", "📉": "chart down", "📊": "bar chart",
    "🗓️": "calendar", "⏰": "alarm clock", "⏳": "hourglass",
    "⌛": "hourglass done", "⏱️": "stopwatch", "🕐": "clock",
    "🧠": "brain", "👀": "eyes look", "👁️": "eye", "🫀": "heart organ",
    "🌱": "seedling plant", "🌿": "herb leaf", "🍀": "clover luck",
    "🌸": "blossom", "🌹": "rose", "🌻": "sunflower", "🌳": "tree",
    "🌲": "evergreen", "🌴": "palm", "🐶": "dog", "🐱": "cat",
    "🐭": "mouse animal", "🐹": "hamster", "🐰": "rabbit",
    "🦊": "fox", "🐻": "bear", "🐼": "panda", "🐨": "koala",
    "🐯": "tiger", "🦁": "lion", "🐮": "cow", "🐷": "pig",
    "🐸": "frog", "🐵": "monkey", "🐔": "chicken", "🐧": "penguin",
    "🐦": "bird", "🦄": "unicorn", "🐝": "bee", "🦋": "butterfly",
    "🐌": "snail", "🐞": "ladybug", "🐢": "turtle", "🐍": "snake",
    "🦎": "lizard", "🐙": "octopus", "🦑": "squid", "🦐": "shrimp",
    "🦀": "crab", "🐡": "fish", "🐠": "tropical fish", "🐟": "fish",
    "🐬": "dolphin", "🐳": "whale", "🦈": "shark", "🐊": "crocodile",
    "🦓": "zebra", "🦒": "giraffe", "🐘": "elephant", "🦏": "rhino",
    "🐪": "camel", "🦙": "llama", "🦌": "deer", "🐺": "wolf",
    "🦉": "owl", "🦇": "bat", "🐓": "rooster", "🦃": "turkey",
    "🦚": "peacock", "🦜": "parrot", "🕊️": "dove peace",
    "🇺🇦": "ukraine flag", "🇺🇸": "usa united states flag",
    "🇬🇧": "uk britain flag", "🇩🇪": "germany flag",
    "🇫🇷": "france flag", "🇵🇱": "poland flag",
    "🇪🇺": "europe eu flag", "🇯🇵": "japan flag",
    "🇨🇦": "canada flag", "🇧🇷": "brazil flag",
    "🏳️‍🌈": "rainbow pride flag", "🏴‍☠️": "pirate flag",
}

ICON_BY_KIND = {
    "image": "image-x-generic",
    "video": "video-x-generic",
    "audio": "audio-x-generic",
    "text": "text-x-generic",
    "font": "font-x-generic",
    "archive": "package-x-generic",
    "pdf": "application-pdf",
    "code": "text-x-script",
    "binary": "application-x-executable",
    "folder": "folder",
}

CODE_EXT = {
    ".py", ".js", ".ts", ".tsx", ".jsx", ".qml", ".rs", ".go", ".c", ".h",
    ".cpp", ".hpp", ".java", ".kt", ".lua", ".sh", ".bash", ".zsh", ".fish",
    ".css", ".scss", ".html", ".json", ".toml", ".yaml", ".yml", ".conf",
    ".desktop", ".service", ".md", ".txt",
}


def strip_vs(text: str) -> str:
    return text.replace("\ufe0f", "").replace("\ufe0e", "")


def build_emoji() -> list[dict]:
    entries: dict[str, dict] = {}
    for low, high in EMOJI_RANGES:
        for cp in range(low, high + 1):
            char = chr(cp)
            name = unicodedata.name(char, "")
            if not name or any(word in name for word in SKIP_WORDS):
                continue
            entries[char] = {
                "char": char,
                "name": name.title().replace(" And ", " and "),
                "search": name.lower().replace("-", " "),
            }

    for key, keywords in ALIASES.items():
        base = strip_vs(key)
        entry = entries.get(base)
        if entry is None:
            entry = {
                "char": key,
                "name": keywords.split()[0].title(),
                "search": "",
            }
            entries[base] = entry
        entry["search"] = (entry["search"] + " " + keywords).strip()

    result = sorted(entries.values(), key=lambda item: item["name"].lower())
    CACHE.mkdir(parents=True, exist_ok=True)
    CACHE.joinpath("emoji-index.json").write_text(
        json.dumps({"version": EMOJI_VERSION, "items": result}, ensure_ascii=False),
        encoding="utf-8",
    )
    return result


def emoji_index() -> list[dict]:
    try:
        data = json.loads(EMOJI_CACHE.read_text(encoding="utf-8"))
        if data.get("version") == EMOJI_VERSION and isinstance(data.get("items"), list):
            return data["items"]
    except (OSError, json.JSONDecodeError):
        pass
    return build_emoji()


def file_icon(path: Path) -> str:
    if path.is_dir():
        return ICON_BY_KIND["folder"]
    suffix = path.suffix.lower()
    if suffix in CODE_EXT:
        return ICON_BY_KIND["code"]
    mime, _ = mimetypes.guess_type(str(path))
    if mime:
        major = mime.split("/", 1)[0]
        if major in ICON_BY_KIND:
            return ICON_BY_KIND[major]
        if mime == "application/pdf":
            return ICON_BY_KIND["pdf"]
        if "zip" in mime or "tar" in mime or "compress" in mime:
            return ICON_BY_KIND["archive"]
    if os.access(path, os.X_OK):
        return ICON_BY_KIND["binary"]
    return ICON_BY_KIND["text"]


EXCLUDES = [
    ".git", "node_modules", ".cache", "target", "__pycache__",
    ".local/share/Trash", ".mozilla", ".var", "flatpak",
    ".rustup", ".cargo/registry", ".npm", ".pnpm-store",
    ".wine", "go/pkg/mod", ".gradle", ".m2", ".nuget", ".vscode",
    "snap", ".local/share/Steam", "venv", ".venv",
    ".vscode-oss", ".claude", ".cursor", ".config/Code", ".config/Cursor",
]


def search_files(raw_query: str, limit: int) -> list[dict]:
    query = raw_query.strip()
    if not query:
        return []

    base = HOME
    pattern = query
    if query.startswith("~/"):
        pattern = query[2:]
    elif query.startswith("/"):
        base = Path("/")
        pattern = query
    elif query.startswith("~"):
        pattern = query[1:]

    absolute_pattern = str(base) != str(HOME)
    full_path = absolute_pattern or "/" in pattern

    fd = shutil.which("fd")
    if fd:
        args = [fd, "--hidden", "--color", "never", "--fixed-strings",
                "--ignore-case", "--max-results", str(limit * 2),
                "--type", "f", "--type", "d"]
        if full_path:
            args.append("--full-path")
        for item in EXCLUDES:
            args.extend(["--exclude", item])
        if str(base) == "/":
            for item in ("proc", "sys", "dev", "run", "boot"):
                args.extend(["--exclude", item])
        args.extend([pattern, str(base)])
    else:
        args = ["find", str(base), "-iname", f"*{pattern}*"]

    try:
        proc = subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
        try:
            out, _ = proc.communicate(timeout=4.0)
        except subprocess.TimeoutExpired:
            proc.kill()
            out, _ = proc.communicate()
    except (OSError, ValueError):
        return []

    results = []
    seen = set()
    for line in out.splitlines():
        line = line.strip()
        if not line or line in seen:
            continue
        seen.add(line)
        path = Path(line)
        if path == HOME:
            continue
        try:
            is_dir = path.is_dir()
        except OSError:
            is_dir = False
        results.append({
            "kind": "file",
            "path": str(path),
            "name": path.name or str(path),
            "dir": str(path.parent),
            "isDir": is_dir,
            "icon": file_icon(path) if not is_dir else ICON_BY_KIND["folder"],
        })

    needle = pattern.lower().replace(str(base).lower(), "")
    needle = needle.strip("/")

    def rank(item: dict):
        name = item["name"].lower()
        position = name.find(needle) if needle else -1
        if position < 0:
            position = item["path"].lower().find(needle) if needle else -1
        depth = item["path"].count(os.sep)
        return (0 if position == 0 else 1, max(0, position), depth, len(item["path"]))

    results.sort(key=rank)
    return results[:limit]


def main() -> int:
    parser = argparse.ArgumentParser(description="Edots launcher data helper")
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("emoji", help="print the emoji index")

    files = sub.add_parser("files", help="search files from $HOME or an absolute path")
    files.add_argument("--query", required=True)
    files.add_argument("--limit", type=int, default=48)

    args = parser.parse_args()
    try:
        if args.command == "emoji":
            payload = {"ok": True, "items": emoji_index()}
        else:
            payload = {"ok": True, "items": search_files(args.query, max(1, min(args.limit, 200)))}
        print(json.dumps(payload, ensure_ascii=False))
        return 0
    except Exception as exc:  # noqa: BLE001 — the launcher needs a readable error
        print(json.dumps({"ok": False, "error": str(exc), "items": []}, ensure_ascii=False))
        return 1


if __name__ == "__main__":
    sys.exit(main())
