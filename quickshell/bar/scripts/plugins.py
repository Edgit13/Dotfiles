#!/usr/bin/env python3
"""Edots plugin discovery and enable/disable state.

A plugin is a directory containing ``plugin.json``::

    {
      "id": "world-clock",
      "name": "World Clock",
      "description": "Local time plus a few cities.",
      "version": "1.0.0",
      "author": "Edots",
      "icon": "public",
      "defaultEnabled": false,
      "surface": { "qml": "WorldClock.qml", "width": 520, "height": 460,
                   "end": true, "typing": false },
      "bar": { "qml": "WorldClockBar.qml", "position": "trailing" }
    }

Search order (first match for an id wins):
  1. ``~/.config/edots/plugins``       — user plugins
  2. ``<quickshell>/bar/plugins``      — bundled examples

State lives in ``~/.config/quickshell/plugins.json``::

    { "enabled": { "world-clock": true } }

Commands:
  list                     JSON for the shell
  status                   human readable summary
  set <id> on|off|toggle   change enabled state
  path                     create and print the user plugin directory
  open                     create the user plugin directory and open it

The helper never executes plugin code. Validation is only about paths and
manifest shape; plugin QML itself is trusted (it runs with your user rights).
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

HOME = Path.home()
CONFIG = Path(os.environ.get("XDG_CONFIG_HOME") or (HOME / ".config")).expanduser()
STATE_FILE = CONFIG / "quickshell" / "plugins.json"
USER_DIR = CONFIG / "edots" / "plugins"
BUNDLED_DIR = Path(__file__).resolve().parent.parent / "plugins"

ID_RE = re.compile(r"^[a-z0-9][a-z0-9._-]{0,63}$")
MAX_ENTRY_BYTES = 1_500_000
SURFACE_DEFAULT_W = 560
SURFACE_DEFAULT_H = 480
SURFACE_MIN_W, SURFACE_MAX_W = 280, 1600
SURFACE_MIN_H, SURFACE_MAX_H = 220, 1200
BAR_POSITIONS = ("leading", "center", "trailing")


class ManifestError(Exception):
    pass


def _read_json(path: Path) -> dict:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise ManifestError("plugin.json is missing") from exc
    except json.JSONDecodeError as exc:
        raise ManifestError(f"plugin.json is not valid JSON (line {exc.lineno})") from exc
    if not isinstance(data, dict):
        raise ManifestError("plugin.json must contain a JSON object")
    return data


def _entry(plugin_dir: Path, value, label: str) -> dict:
    if not isinstance(value, dict):
        raise ManifestError(f"{label} must be an object")
    qml = value.get("qml")
    if not isinstance(qml, str) or not qml.strip():
        raise ManifestError(f"{label}.qml is required")
    if not qml.endswith(".qml"):
        raise ManifestError(f"{label}.qml must be a .qml file")

    base = plugin_dir.resolve()
    target = (base / qml).resolve()
    try:
        target.relative_to(base)
    except ValueError as exc:
        raise ManifestError(f"{label}.qml must stay inside the plugin folder") from exc
    if not target.is_file():
        raise ManifestError(f"{label}.qml not found: {qml}")
    try:
        size = target.stat().st_size
    except OSError as exc:
        raise ManifestError(f"cannot read {label}.qml: {exc}") from exc
    if size > MAX_ENTRY_BYTES:
        raise ManifestError(f"{label}.qml is too large ({size} bytes)")
    return {"qml": str(target), "size": size}


def _int(value, fallback: int, low: int, high: int) -> int:
    try:
        number = int(value)
    except (TypeError, ValueError):
        return fallback
    return max(low, min(high, number))


def _bool(value, fallback: bool = False) -> bool:
    if isinstance(value, bool):
        return value
    if isinstance(value, str):
        return value.strip().lower() in ("1", "true", "yes", "on")
    if isinstance(value, (int, float)):
        return bool(value)
    return fallback


def load_state() -> dict:
    if not STATE_FILE.is_file():
        return {"enabled": {}}
    try:
        data = json.loads(STATE_FILE.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {"enabled": {}}
    if not isinstance(data, dict):
        return {"enabled": {}}
    enabled = data.get("enabled")
    if not isinstance(enabled, dict):
        data["enabled"] = {}
    return data


def save_state(state: dict) -> None:
    STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
    payload = json.dumps(state, ensure_ascii=False, indent=2) + "\n"
    fd, tmp = tempfile.mkstemp(prefix=".plugins-", suffix=".json", dir=str(STATE_FILE.parent))
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(payload)
        os.replace(tmp, STATE_FILE)
    finally:
        try:
            os.unlink(tmp)
        except FileNotFoundError:
            pass


def enabled_for(plugin_id: str, manifest: dict, state: dict) -> bool:
    values = state.get("enabled") or {}
    if plugin_id in values:
        return _bool(values[plugin_id])
    return _bool(manifest.get("defaultEnabled"), False)


def plugin_dirs():
    return (("user", USER_DIR), ("bundled", BUNDLED_DIR))


def discover() -> tuple[list[dict], list[dict]]:
    state = load_state()
    plugins: list[dict] = []
    errors: list[dict] = []
    seen: set[str] = set()

    for source, root in plugin_dirs():
        if not root.is_dir():
            continue
        for folder in sorted(root.iterdir(), key=lambda item: item.name.lower()):
            if not folder.is_dir() or folder.name.startswith("."):
                continue
            if not (folder / "plugin.json").is_file():
                continue
            try:
                manifest = _read_json(folder / "plugin.json")
                plugin_id = manifest.get("id")
                if not isinstance(plugin_id, str) or not ID_RE.match(plugin_id):
                    raise ManifestError(
                        "id must match [a-z0-9][a-z0-9._-]* and be at most 64 characters"
                    )
                if plugin_id in seen:
                    if source == "bundled":
                        # A user plugin with the same id overrides the bundled one.
                        continue
                    raise ManifestError(f"duplicate plugin id: {plugin_id}")

                name = manifest.get("name")
                if not isinstance(name, str) or not name.strip():
                    name = plugin_id
                description = manifest.get("description")
                if not isinstance(description, str):
                    description = ""
                version = manifest.get("version")
                if not isinstance(version, str):
                    version = ""
                author = manifest.get("author")
                if not isinstance(author, str):
                    author = ""
                icon = manifest.get("icon")
                if not isinstance(icon, str) or not icon.strip():
                    icon = "extension"

                surface = None
                if manifest.get("surface") is not None:
                    entry = _entry(folder, manifest.get("surface"), "surface")
                    raw = manifest["surface"]
                    surface = {
                        "qml": entry["qml"],
                        "size": entry["size"],
                        "w": _int(raw.get("width"), SURFACE_DEFAULT_W, SURFACE_MIN_W, SURFACE_MAX_W),
                        "h": _int(raw.get("height"), SURFACE_DEFAULT_H, SURFACE_MIN_H, SURFACE_MAX_H),
                        "end": _bool(raw.get("end"), False),
                        "typing": _bool(raw.get("typing"), False),
                    }

                bar = None
                if manifest.get("bar") is not None:
                    entry = _entry(folder, manifest.get("bar"), "bar")
                    raw = manifest["bar"]
                    position = raw.get("position", "trailing")
                    if position not in BAR_POSITIONS:
                        raise ManifestError(
                            "bar.position must be one of: " + ", ".join(BAR_POSITIONS)
                        )
                    order = _int(raw.get("order"), 100, -10000, 10000)
                    bar = {
                        "qml": entry["qml"],
                        "size": entry["size"],
                        "position": position,
                        "order": order,
                    }

                if surface is None and bar is None:
                    raise ManifestError("plugin has neither a surface nor a bar entry")

                seen.add(plugin_id)
                plugins.append(
                    {
                        "id": plugin_id,
                        "name": name.strip(),
                        "description": description.strip(),
                        "version": version.strip(),
                        "author": author.strip(),
                        "icon": icon,
                        "source": source,
                        "dir": str(folder.resolve()),
                        "enabled": enabled_for(plugin_id, manifest, state),
                        "defaultEnabled": _bool(manifest.get("defaultEnabled"), False),
                        "surface": surface,
                        "bar": bar,
                    }
                )
            except (ManifestError, OSError) as exc:
                errors.append(
                    {
                        "folder": str(folder),
                        "name": folder.name,
                        "source": source,
                        "error": str(exc),
                    }
                )

    plugins.sort(key=lambda item: (item["name"].lower(), item["id"]))
    errors.sort(key=lambda item: (item["source"], item["name"].lower()))
    return plugins, errors


def command_list() -> int:
    plugins, errors = discover()
    print(
        json.dumps(
            {
                "ok": True,
                "stateFile": str(STATE_FILE),
                "userDir": str(USER_DIR),
                "bundledDir": str(BUNDLED_DIR),
                "plugins": plugins,
                "errors": errors,
            },
            ensure_ascii=False,
        )
    )
    return 0


def command_status() -> int:
    plugins, errors = discover()
    if not plugins and not errors:
        print("No plugins found.")
    for plugin in plugins:
        mark = "on " if plugin["enabled"] else "off"
        kinds = []
        if plugin["surface"]:
            kinds.append("surface")
        if plugin["bar"]:
            kinds.append("bar/" + plugin["bar"]["position"])
        print(
            f"[{mark}] {plugin['id']:<28} {plugin['source']:<7} "
            f"{', '.join(kinds):<20} {plugin['name']}"
        )
    for error in errors:
        print(f"[err] {error['name']:<28} {error['source']:<7} {error['error']}", file=sys.stderr)
    print(f"\nstate: {STATE_FILE}")
    return 0


def _find_plugin(plugin_id: str) -> dict | None:
    plugins, _ = discover()
    for plugin in plugins:
        if plugin["id"] == plugin_id:
            return plugin
    return None


def command_set(plugin_id: str, value: str) -> int:
    plugin = _find_plugin(plugin_id)
    if plugin is None:
        print(json.dumps({"ok": False, "error": f"unknown plugin: {plugin_id}"}), file=sys.stderr)
        return 2

    if value == "toggle":
        new_value = not plugin["enabled"]
    elif value in ("on", "true", "1", "enable", "enabled"):
        new_value = True
    elif value in ("off", "false", "0", "disable", "disabled"):
        new_value = False
    else:
        print(json.dumps({"ok": False, "error": "value must be on, off or toggle"}), file=sys.stderr)
        return 2

    state = load_state()
    enabled = state.get("enabled")
    if not isinstance(enabled, dict):
        enabled = {}
    enabled[plugin_id] = new_value
    state["enabled"] = enabled
    try:
        save_state(state)
    except OSError as exc:
        print(json.dumps({"ok": False, "error": str(exc)}), file=sys.stderr)
        return 1

    print(
        json.dumps(
            {"ok": True, "id": plugin_id, "enabled": new_value, "stateFile": str(STATE_FILE)},
            ensure_ascii=False,
        )
    )
    return 0


def command_path(open_folder: bool = False) -> int:
    USER_DIR.mkdir(parents=True, exist_ok=True)
    print(str(USER_DIR))
    if open_folder:
        try:
            subprocess.Popen(
                ["xdg-open", str(USER_DIR)],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                start_new_session=True,
            )
        except OSError:
            return 1
    return 0


def usage() -> None:
    print(__doc__.strip())


def main(argv: list[str]) -> int:
    if not argv or argv[0] in ("-h", "--help", "help"):
        usage()
        return 0

    command = argv[0]
    if command == "list":
        return command_list()
    if command == "status":
        return command_status()
    if command == "set":
        if len(argv) < 3:
            print("usage: plugins.py set <id> on|off|toggle", file=sys.stderr)
            return 2
        return command_set(argv[1], argv[2])
    if command == "path":
        return command_path(False)
    if command == "open":
        return command_path(True)

    print(f"unknown command: {command}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
