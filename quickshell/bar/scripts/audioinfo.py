#!/usr/bin/env python3
"""
audioinfo.py - PipeWire / PulseAudio devices, streams and per-app routing for Edots.

Commands
--------
  list                     devices, streams, saved routes (default; JSON)
  status                   human-readable apps and saved routes
  route <app> <sink|auto>  pin an app to a sink, or clear the pin with "auto"
  apply                    move running streams to their saved sinks
  sinks                    print available sinks (human readable)

Devices and streams come from `pactl`. Per-app output routes live in
<XDG_CONFIG_HOME>/quickshell/per-app-audio.json:

    { "routes": { "org.mozilla.firefox": "alsa_output.pci-...analog-stereo" } }

Routes are keyed by application id, falling back to the process binary and
finally the application name, so they survive restarts and stream index
changes.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path

CONFIG_HOME = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config")
STATE_FILE = CONFIG_HOME / "quickshell" / "per-app-audio.json"

AUTO_VALUES = {"auto", "default", "follow", "off", ""}


# ────────────────────────────── utilities ──────────────────────────────


def clean(value) -> str:
    if value is None:
        return ""
    return str(value).strip().strip('"')


def run_json(*args: str):
    try:
        output = subprocess.check_output(
            ["pactl", "-f", "json", *args],
            text=True,
            stderr=subprocess.DEVNULL,
        )
        return json.loads(output)
    except Exception:
        return []


def run_pactl(*args: str) -> bool:
    return subprocess.run(
        ["pactl", *args],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    ).returncode == 0


def volume_percent(entry) -> int:
    if not entry.get("volume"):
        return 0
    first = list(entry["volume"].values())[0]
    value = clean(first.get("value_percent", "0%")).replace("%", "")
    try:
        return int(value)
    except ValueError:
        return 0


def load_routes() -> dict[str, str]:
    try:
        data = json.loads(STATE_FILE.read_text(encoding="utf-8"))
    except Exception:
        return {}
    routes = data.get("routes") if isinstance(data, dict) else None
    if not isinstance(routes, dict):
        return {}
    return {
        str(key): str(value)
        for key, value in routes.items()
        if isinstance(key, str) and isinstance(value, str) and value
    }


def save_routes(routes: dict[str, str]) -> None:
    STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
    tmp = STATE_FILE.with_name(STATE_FILE.name + ".tmp")
    tmp.write_text(
        json.dumps({"routes": routes}, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    os.replace(tmp, STATE_FILE)


def app_key(props: dict) -> str:
    """Stable identity for an app across stream restarts."""
    for prop in ("application.id", "application.process.binary", "application.name"):
        value = clean(props.get(prop))
        if value:
            return value.lower()
    return ""


def app_icon(props: dict) -> str:
    for prop in ("application.icon_name", "application.icon-name", "application.icon"):
        value = clean(props.get(prop))
        if value:
            return value
    return ""


# ────────────────────────────── devices ──────────────────────────────


def read_sinks() -> list[dict]:
    default = ""
    try:
        default = clean(subprocess.check_output(
            ["pactl", "get-default-sink"], text=True, stderr=subprocess.DEVNULL
        ))
    except Exception:
        pass

    sinks = []
    for sink in run_json("list", "sinks"):
        name = clean(sink.get("name"))
        sinks.append({
            "index": sink.get("index", 0),
            "name": name,
            "description": clean(sink.get("description")) or name,
            "volume": volume_percent(sink),
            "muted": bool(sink.get("mute", False)),
            "isDefault": name == default,
            "activePort": clean(sink.get("active_port")),
            "ports": [
                clean(port.get("description") or port.get("name"))
                for port in sink.get("ports", [])
            ],
        })
    return sinks


def read_sources() -> list[dict]:
    default = ""
    try:
        default = clean(subprocess.check_output(
            ["pactl", "get-default-source"], text=True, stderr=subprocess.DEVNULL
        ))
    except Exception:
        pass

    sources = []
    for source in run_json("list", "sources"):
        name = clean(source.get("name"))
        if name.endswith(".monitor"):
            continue
        sources.append({
            "index": source.get("index", 0),
            "name": name,
            "description": clean(source.get("description")) or name,
            "volume": volume_percent(source),
            "muted": bool(source.get("mute", False)),
            "isDefault": name == default,
            "activePort": clean(source.get("active_port")),
            "ports": [
                clean(port.get("description") or port.get("name"))
                for port in source.get("ports", [])
            ],
        })
    return sources


def read_streams(sinks: list[dict], routes: dict[str, str]) -> list[dict]:
    sinks_by_index = {sink["index"]: sink for sink in sinks}
    streams = []
    for stream in run_json("list", "sink-inputs"):
        props = stream.get("properties", {}) or {}
        key = app_key(props)
        sink = sinks_by_index.get(stream.get("sink", 0))
        streams.append({
            "index": stream.get("index", 0),
            "name": clean(props.get("application.name")) or clean(props.get("media.name")) or "Audio stream",
            "binary": clean(props.get("application.process.binary")),
            "appId": clean(props.get("application.id")),
            "icon": app_icon(props),
            "key": key,
            "media": clean(props.get("media.name")),
            "volume": volume_percent(stream),
            "muted": bool(stream.get("mute", False)),
            "sink": stream.get("sink", 0),
            "sinkName": sink["name"] if sink else "",
            "sinkDescription": sink["description"] if sink else "",
            "pinned": routes.get(key, "") if key else "",
        })
    return streams


def snapshot() -> dict:
    routes = load_routes()
    sinks = read_sinks()
    streams = read_streams(sinks, routes)
    return {
        "ok": True,
        "stateFile": str(STATE_FILE),
        "defaultSink": next((s["name"] for s in sinks if s["isDefault"]),
                            sinks[0]["name"] if sinks else ""),
        "sinks": sinks,
        "sources": read_sources(),
        "streams": streams,
        "routes": routes,
    }


# ────────────────────────────── routing ──────────────────────────────


def resolve_sink(query: str, sinks: list[dict]) -> dict | None:
    needle = clean(query).lower()
    if not needle:
        return None
    for sink in sinks:
        if sink["name"].lower() == needle:
            return sink
    for sink in sinks:
        if str(sink["index"]) == needle:
            return sink
    for sink in sinks:
        if needle in sink["description"].lower():
            return sink
    return None


def resolve_key(query: str, streams: list[dict], routes: dict[str, str]) -> str:
    """Resolve an app by route key, display name, binary or app id."""
    needle = clean(query).lower()
    if not needle:
        return ""
    if needle in routes:
        return needle

    for stream in streams:
        if stream["key"] == needle:
            return stream["key"]
    for stream in streams:
        haystack = " ".join([
            stream["name"], stream["binary"], stream["appId"], stream["key"],
        ]).lower()
        if needle in haystack:
            return stream["key"]
    for key in routes:
        if needle in key:
            return key
    # Allow pre-configuring an app that is not running yet.
    return needle


def move_stream(index: int, sink_name: str) -> bool:
    if not sink_name:
        return False
    return run_pactl("move-sink-input", str(index), sink_name)


def command_route(query: str, sink_query: str) -> dict:
    routes = load_routes()
    sinks = read_sinks()
    streams = read_streams(sinks, routes)
    key = resolve_key(query, streams, routes)

    if not key:
        return {"ok": False, "error": "app is required"}

    if clean(sink_query).lower() in AUTO_VALUES:
        removed = routes.pop(key, None)
        save_routes(routes)
        moved = 0
        for stream in streams:
            if stream["key"] != key:
                continue
            default = next((s["name"] for s in sinks if s["isDefault"]), "")
            if default and move_stream(stream["index"], default):
                moved += 1
        return {
            "ok": True, "key": key, "sink": "", "removed": removed,
            "routes": routes, "moved": moved,
        }

    sink = resolve_sink(sink_query, sinks)
    if sink is None:
        return {
            "ok": False,
            "error": f"unknown sink: {sink_query}",
            "sinks": [{"name": s["name"], "description": s["description"]} for s in sinks],
        }

    routes[key] = sink["name"]
    save_routes(routes)
    moved = 0
    for stream in streams:
        if stream["key"] == key and move_stream(stream["index"], sink["name"]):
            moved += 1
    return {
        "ok": True, "key": key, "sink": sink["name"],
        "sinkDescription": sink["description"], "routes": routes, "moved": moved,
    }


def command_apply() -> dict:
    routes = load_routes()
    sinks = read_sinks()
    streams = read_streams(sinks, routes)
    moved = []
    for stream in streams:
        wanted = routes.get(stream["key"], "")
        if not wanted or wanted == stream["sinkName"]:
            continue
        if move_stream(stream["index"], wanted):
            moved.append({"index": stream["index"], "app": stream["key"], "sink": wanted})
    return {"ok": True, "moved": moved, "routes": routes}


# ────────────────────────────── CLI ──────────────────────────────


def command_status() -> int:
    data = snapshot()
    streams = data["streams"]
    routes = data["routes"]
    sinks = data["sinks"]

    if streams:
        print(f"{'APP':<28} {'VOL':>4}  {'OUTPUT':<28} PIN")
        for stream in streams:
            name = (stream["name"] or stream["binary"] or "Audio stream")[:27]
            output = (stream["sinkDescription"] or stream["sinkName"] or "—")[:27]
            pin = "yes" if stream["key"] in routes else ""
            muted = " (muted)" if stream["muted"] else ""
            print(f"{name:<28} {stream['volume']:>3}%  {output:<28} {pin}{muted}")
    else:
        print("No active audio streams.")

    if routes:
        print("\nSaved routes:")
        descriptions = {sink["name"]: sink["description"] for sink in sinks}
        for key, sink_name in sorted(routes.items()):
            label = descriptions.get(sink_name, sink_name)
            print(f"  {key}  →  {label}")
    else:
        print("\nNo saved per-app routes.")
    return 0


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", nargs="?", default="list",
                        choices=["list", "status", "route", "apply", "sinks"])
    parser.add_argument("args", nargs="*")
    parsed = parser.parse_args(argv)

    if parsed.command == "list":
        print(json.dumps(snapshot(), ensure_ascii=False))
        return 0

    if parsed.command == "status":
        return command_status()

    if parsed.command == "sinks":
        for sink in read_sinks():
            mark = "*" if sink["isDefault"] else " "
            print(f"{mark} {sink['index']:>3}  {sink['description']}")
            print(f"      {sink['name']}")
        return 0

    if parsed.command == "route":
        if len(parsed.args) < 2:
            print(json.dumps({"ok": False, "error": "usage: audioinfo.py route <app> <sink|auto>"}))
            return 2
        query = parsed.args[0]
        # Join the rest so unquoted sink descriptions still work.
        sink_query = " ".join(parsed.args[1:])
        result = command_route(query, sink_query)
        print(json.dumps(result, ensure_ascii=False))
        return 0 if result.get("ok") else 1

    if parsed.command == "apply":
        print(json.dumps(command_apply(), ensure_ascii=False))
        return 0

    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
