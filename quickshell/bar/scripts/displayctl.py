#!/usr/bin/env python3
"""Edots display control helper — runtime output management for wlroots/MangoWC.

Commands
--------
  list                 print the current outputs as JSON (wlr-randr --json)
  apply '<spec>'       apply an output specification (JSON)
  revert               restore the setup saved before the last apply
  keep                 forget the saved setup (confirm the new one)

A spec is ``{"outputs": [...]}``; every entry may contain:

  name          output name, e.g. "eDP-1"
  enabled       bool
  mode          {"width": 1920, "height": 1080, "refresh": 60.02}
  scale         float 0.5–3.0
  transform     normal | 90 | 180 | 270 | flipped | flipped-90 | ...
  adaptiveSync  bool
  position      {"x": 0, "y": 0}                 absolute layout position
  relative      {"to": "HDMI-A-1", "where": "right"}  left|right|above|below

The previous configuration is written to
``~/.cache/quickshell/display-snapshot.json`` before every apply, so the UI
can offer a keep/revert countdown and ``edots display revert`` works even if
the shell restarts.
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

CACHE = Path(os.environ.get("XDG_CACHE_HOME") or Path.home() / ".cache") / "quickshell"
SNAPSHOT = CACHE / "display-snapshot.json"

TRANSFORMS = (
    "normal", "90", "180", "270",
    "flipped", "flipped-90", "flipped-180", "flipped-270",
)
RELATIVE = ("left", "right", "above", "below")


class DisplayError(Exception):
    pass


def run(args: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(args, text=True, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, check=False)


def emit(payload: dict) -> None:
    print(json.dumps(payload, ensure_ascii=False))


def wlr_json() -> list[dict]:
    if not shutil.which("wlr-randr"):
        raise DisplayError("wlr-randr is not installed. Install it with: sudo pacman -S wlr-randr")
    result = run(["wlr-randr", "--json"])
    if result.returncode:
        raise DisplayError(result.stderr.strip() or "wlr-randr failed")
    try:
        data = json.loads(result.stdout)
    except json.JSONDecodeError as exc:
        raise DisplayError(f"Could not parse wlr-randr output: {exc}") from exc
    if not isinstance(data, list):
        raise DisplayError("Unexpected wlr-randr output")
    return data


def mode_id(mode: dict) -> str:
    return f"{mode['width']}x{mode['height']}@{float(mode['refresh']):.2f}"


def mode_label(mode: dict) -> str:
    label = f"{mode['width']} × {mode['height']} · {float(mode['refresh']):.2f} Hz"
    if mode.get("preferred"):
        label += " · preferred"
    return label


def normalize(outputs: list[dict]) -> list[dict]:
    normalized = []
    for raw in outputs:
        modes = []
        for mode in raw.get("modes") or []:
            item = {
                "id": mode_id(mode),
                "label": mode_label(mode),
                "width": int(mode["width"]),
                "height": int(mode["height"]),
                "refresh": round(float(mode["refresh"]), 6),
                "preferred": bool(mode.get("preferred")),
                "current": bool(mode.get("current")),
            }
            modes.append(item)

        current = next((m for m in modes if m["current"]), None)
        if current is None:
            current = next((m for m in modes if m["preferred"]), None)
        if current is None and modes:
            current = modes[0]

        position = raw.get("position") or {}
        physical = raw.get("physical_size") or {}
        normalized.append({
            "name": raw.get("name", ""),
            "description": raw.get("description") or "",
            "make": raw.get("make") or "",
            "model": raw.get("model") or "",
            "serial": raw.get("serial"),
            "physicalSize": {
                "width": int(physical.get("width") or 0),
                "height": int(physical.get("height") or 0),
            },
            "enabled": bool(raw.get("enabled")),
            "modes": modes,
            "currentMode": current["id"] if current else "",
            "scale": float(raw.get("scale") or 1.0),
            "transform": raw.get("transform") or "normal",
            "position": {
                "x": int(position.get("x") or 0),
                "y": int(position.get("y") or 0),
            },
            "adaptiveSync": bool(raw.get("adaptive_sync")),
        })
    return normalized


def load_outputs() -> list[dict]:
    return normalize(wlr_json())


def current_spec(outputs: list[dict]) -> dict:
    entries = []
    for output in outputs:
        entry = {
            "name": output["name"],
            "enabled": output["enabled"],
            "scale": output["scale"],
            "transform": output["transform"],
            "adaptiveSync": output["adaptiveSync"],
            "position": dict(output["position"]),
        }
        mode = next((m for m in output["modes"] if m["id"] == output["currentMode"]), None)
        if mode is not None:
            entry["mode"] = {
                "width": mode["width"],
                "height": mode["height"],
                "refresh": mode["refresh"],
            }
        entries.append(entry)
    return {"outputs": entries}


def save_snapshot(spec: dict) -> None:
    CACHE.mkdir(parents=True, exist_ok=True)
    SNAPSHOT.write_text(json.dumps(spec, ensure_ascii=False, indent=2), encoding="utf-8")


def read_snapshot() -> dict | None:
    try:
        data = json.loads(SNAPSHOT.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None
    return data if isinstance(data, dict) else None


def resolve_mode(output: dict, wanted) -> dict:
    modes = output["modes"]
    if not modes:
        raise DisplayError(f"{output['name']} reports no available modes")
    if wanted is None or wanted == "":
        current = next((m for m in modes if m["id"] == output["currentMode"]), None)
        preferred = next((m for m in modes if m["preferred"]), modes[0])
        return current or preferred

    if isinstance(wanted, str):
        exact = next((m for m in modes if m["id"] == wanted), None)
        if exact is not None:
            return exact
        text = wanted.removesuffix("Hz")
        if "@" in text:
            resolution, _, refresh = text.partition("@")
            try:
                wanted = {
                    "width": int(resolution.split("x", 1)[0]),
                    "height": int(resolution.split("x", 1)[1]),
                    "refresh": float(refresh),
                }
            except (ValueError, IndexError):
                raise DisplayError(f"Invalid mode {wanted!r}") from None
        else:
            try:
                width, height = text.lower().split("x", 1)
                wanted = {"width": int(width), "height": int(height)}
            except ValueError:
                raise DisplayError(f"Invalid mode {wanted!r}") from None

    if not isinstance(wanted, dict):
        raise DisplayError(f"Invalid mode {wanted!r}")

    width = int(wanted.get("width") or 0)
    height = int(wanted.get("height") or 0)
    refresh = wanted.get("refresh")
    matches = [m for m in modes if m["width"] == width and m["height"] == height]
    if refresh is not None:
        try:
            refresh_value = float(refresh)
        except (TypeError, ValueError):
            raise DisplayError(f"Invalid refresh rate {refresh!r}") from None
        matches = [m for m in matches if abs(m["refresh"] - refresh_value) < 0.05]
    if not matches:
        available = ", ".join(m["id"] for m in modes)
        raise DisplayError(f"Mode {width}x{height} is not available on {output['name']} (have: {available})")
    return matches[0]


def mode_args(mode: dict) -> list[str]:
    return ["--mode", f"{mode['width']}x{mode['height']}@{mode['refresh']:g}"]


def validate(spec: dict, outputs: list[dict]) -> list[dict]:
    by_name = {item["name"]: item for item in outputs}
    entries = spec.get("outputs")
    if not isinstance(entries, list) or not entries:
        raise DisplayError("The display specification is empty")

    plan = []
    seen = set()
    enabled_count = 0
    for entry in entries:
        if not isinstance(entry, dict):
            raise DisplayError("Invalid display entry")
        name = str(entry.get("name") or "")
        if not name:
            raise DisplayError("A display entry has no name")
        if name in seen:
            raise DisplayError(f"Display {name!r} appears more than once")
        seen.add(name)
        output = by_name.get(name)
        if output is None:
            raise DisplayError(f"Display {name!r} is not currently connected")

        enabled = bool(entry.get("enabled", True))
        scale = float(entry.get("scale", output["scale"]) or 1.0)
        if not 0.5 <= scale <= 3.0:
            raise DisplayError(f"Scale {scale:g} is outside 0.5–3.0 for {name}")
        transform = str(entry.get("transform") or output["transform"])
        if transform not in TRANSFORMS:
            raise DisplayError(f"Unknown transform {transform!r} for {name}")

        relative = entry.get("relative")
        if relative is not None:
            if not isinstance(relative, dict):
                raise DisplayError(f"Invalid arrangement for {name}")
            target = str(relative.get("to") or "")
            where = str(relative.get("where") or "")
            if where not in RELATIVE:
                raise DisplayError(f"Unknown arrangement {where!r} for {name}")
            if target == name:
                raise DisplayError(f"{name} cannot be positioned relative to itself")
            target_output = by_name.get(target)
            if target_output is None:
                raise DisplayError(f"Arrangement target {target!r} is not connected")
            if not bool(target_output["enabled"]):
                raise DisplayError(f"Arrangement target {target!r} is disabled")

        position = entry.get("position")
        if position is not None:
            if not isinstance(position, dict):
                raise DisplayError(f"Invalid position for {name}")
            position = {"x": int(position.get("x") or 0), "y": int(position.get("y") or 0)}

        mode = None
        if enabled:
            enabled_count += 1
            mode = resolve_mode(output, entry.get("mode"))
            mode = {"width": mode["width"], "height": mode["height"], "refresh": mode["refresh"]}

        plan.append({
            "name": name,
            "enabled": enabled,
            "mode": mode,
            "scale": scale,
            "transform": transform,
            "adaptiveSync": bool(entry.get("adaptiveSync", output["adaptiveSync"])),
            "relative": relative,
            "position": position,
        })

    if enabled_count == 0:
        raise DisplayError("At least one display must stay enabled")
    return plan


def apply_plan(plan: list[dict]) -> None:
    # 1. Turn outputs on and give them their mode / scale / transform.
    for item in plan:
        if not item["enabled"]:
            continue
        args = ["wlr-randr", "--output", item["name"], "--on"]
        args += mode_args(item["mode"])
        args += ["--scale", f"{item['scale']:g}"]
        args += ["--transform", item["transform"]]
        args += ["--adaptive-sync", "enabled" if item["adaptiveSync"] else "disabled"]
        result = run(args)
        if result.returncode:
            raise DisplayError(result.stderr.strip() or f"Could not configure {item['name']}")

    # 2. Position / arrange after every output is on.
    for item in plan:
        if not item["enabled"]:
            continue
        relative = item["relative"]
        if relative is not None:
            args = ["wlr-randr", "--output", item["name"],
                    f"--{relative['where']}-of", str(relative["to"])]
        elif item["position"] is not None:
            args = ["wlr-randr", "--output", item["name"],
                    "--pos", f"{item['position']['x']},{item['position']['y']}"]
        else:
            continue
        result = run(args)
        if result.returncode:
            raise DisplayError(result.stderr.strip() or f"Could not arrange {item['name']}")

    # 3. Disable the rest only after something else is already on.
    for item in plan:
        if item["enabled"]:
            continue
        result = run(["wlr-randr", "--output", item["name"], "--off"])
        if result.returncode:
            raise DisplayError(result.stderr.strip() or f"Could not disable {item['name']}")


def apply_spec(spec: dict, save: bool) -> dict:
    outputs = load_outputs()
    plan = validate(spec, outputs)
    snapshot = current_spec(outputs)
    if save:
        save_snapshot(snapshot)
    try:
        apply_plan(plan)
    except DisplayError:
        # Best effort: put the user's setup back before reporting the failure.
        rollback = validate(snapshot, load_outputs())
        try:
            apply_plan(rollback)
        except (DisplayError, OSError):
            pass
        raise
    return {"ok": True, "message": "Display settings applied", "outputs": len(plan)}


def command_list() -> int:
    try:
        outputs = load_outputs()
    except DisplayError as exc:
        emit({"ok": False, "error": str(exc), "outputs": []})
        return 0
    emit({"ok": True, "outputs": outputs, "canRevert": SNAPSHOT.exists()})
    return 0


def parse_spec(raw: str) -> dict:
    if raw == "-":
        raw = sys.stdin.read()
    try:
        spec = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise DisplayError(f"Invalid display specification: {exc}") from exc
    if isinstance(spec, list):
        spec = {"outputs": spec}
    if not isinstance(spec, dict):
        raise DisplayError("Invalid display specification")
    return spec


def command_apply(raw: str) -> int:
    try:
        payload = apply_spec(parse_spec(raw), save=True)
    except (DisplayError, OSError, ValueError) as exc:
        emit({"ok": False, "error": str(exc)})
        return 1
    emit(payload)
    return 0


def command_revert() -> int:
    snapshot = read_snapshot()
    if snapshot is None:
        emit({"ok": False, "error": "No display setup to revert"})
        return 2
    try:
        apply_spec(snapshot, save=False)
    except (DisplayError, OSError, ValueError) as exc:
        emit({"ok": False, "error": str(exc)})
        return 1
    try:
        SNAPSHOT.unlink()
    except OSError:
        pass
    emit({"ok": True, "message": "Previous display setup restored"})
    return 0


def command_keep() -> int:
    try:
        SNAPSHOT.unlink()
    except FileNotFoundError:
        pass
    except OSError as exc:
        emit({"ok": False, "error": str(exc)})
        return 1
    emit({"ok": True, "message": "Display setup kept"})
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Edots display control helper")
    sub = parser.add_subparsers(dest="action", required=True)
    sub.add_parser("list")
    apply_parser = sub.add_parser("apply")
    apply_parser.add_argument("spec")
    sub.add_parser("revert")
    sub.add_parser("keep")
    args = parser.parse_args()

    if args.action == "list":
        return command_list()
    if args.action == "apply":
        return command_apply(args.spec)
    if args.action == "revert":
        return command_revert()
    return command_keep()


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        raise SystemExit(130)
