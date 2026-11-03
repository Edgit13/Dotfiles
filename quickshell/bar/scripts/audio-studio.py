#!/usr/bin/env python3
"""Edots Audio Studio helper.

Builds EasyEffects presets on the fly for a 10-band output equalizer and a
microphone RNNoise filter, loads them into the running EasyEffects service and
prints a small JSON status that the Quickshell surface consumes.

The helper never edits the user's own presets: it owns exactly three files:

    <XDG_DATA_HOME>/easyeffects/output/Edots Studio.json
    <XDG_DATA_HOME>/easyeffects/input/Edots Mic NR.json
    <XDG_DATA_HOME>/easyeffects/input/Edots Mic Off.json

Runtime state (gains, preamp, last choice) lives in
~/.config/quickshell/audio-studio.json so the UI can restore itself.
"""
from __future__ import annotations

import argparse
import json
import math
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

HOME = Path.home()
DATA_HOME = Path(os.environ.get("XDG_DATA_HOME") or HOME / ".local/share")
CONFIG_HOME = Path(os.environ.get("XDG_CONFIG_HOME") or HOME / ".config")
OUT_DIR = DATA_HOME / "easyeffects" / "output"
IN_DIR = DATA_HOME / "easyeffects" / "input"
STATE_FILE = CONFIG_HOME / "quickshell" / "audio-studio.json"

FREQS = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
FREQ_LABELS = ["32", "64", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"]
GAIN_MIN = -12.0
GAIN_MAX = 12.0

STUDIO_PRESET = "Edots Studio"
MIC_ON_PRESET = "Edots Mic NR"
MIC_OFF_PRESET = "Edots Mic Off"
GENERATED = {STUDIO_PRESET, MIC_ON_PRESET, MIC_OFF_PRESET}

BUILTINS = {
    "Flat": [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
    "Bass boost": [6.0, 5.0, 3.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
    "Vocal": [-2.0, -1.0, 0.0, 1.0, 3.0, 4.0, 3.0, 1.0, 0.0, -1.0],
    "Treble": [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 3.0, 5.0, 6.0],
    "Warm": [4.0, 3.0, 2.0, 1.0, 0.0, -1.0, -1.0, 0.0, 1.0, 2.0],
}


# ────────────────────────────── utilities ──────────────────────────────


def clamp(value: float, low: float = GAIN_MIN, high: float = GAIN_MAX) -> float:
    return max(low, min(high, value))


def write_json(path: Path, data) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    os.replace(tmp, path)


def ee_bin() -> str | None:
    return shutil.which("easyeffects")


def run_ee(extra: list[str], timeout: float = 8.0) -> subprocess.CompletedProcess[str]:
    binary = ee_bin()
    if not binary:
        raise RuntimeError("EasyEffects is not installed")
    return subprocess.run([binary, *extra], text=True, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, timeout=timeout, check=False)


def is_running() -> bool:
    return subprocess.run(["pgrep", "-x", "easyeffects"], stdout=subprocess.DEVNULL,
                          stderr=subprocess.DEVNULL, check=False).returncode == 0


def ensure_engine() -> bool:
    if not ee_bin():
        return False
    if is_running():
        return True
    subprocess.Popen([ee_bin(), "--service-mode", "--hide-window"],
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                     start_new_session=True)
    for _ in range(45):
        if is_running():
            return True
        time.sleep(0.1)
    return is_running()


def preset_name(raw: str) -> str:
    """First non-empty line of `easyeffects -a output|input`."""
    for line in raw.splitlines():
        line = line.strip()
        if line:
            return line
    return ""


def default_state() -> dict:
    return {
        "gains": [0.0] * 10,
        "preamp": 0.0,
        "preset": "Flat",
        "loadedOutput": "",
        "loadedInput": "",
        "mic": False,
    }


def read_state() -> dict:
    state = default_state()
    try:
        data = json.loads(STATE_FILE.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return state
    if not isinstance(data, dict):
        return state

    gains = data.get("gains")
    if isinstance(gains, list) and len(gains) == 10:
        try:
            state["gains"] = [round(clamp(float(g)), 1) for g in gains]
        except (TypeError, ValueError):
            pass
    try:
        state["preamp"] = round(clamp(float(data.get("preamp", 0.0))), 1)
    except (TypeError, ValueError):
        pass
    preset = data.get("preset")
    if isinstance(preset, str) and preset:
        state["preset"] = preset
    state["mic"] = bool(data.get("mic", False))
    for key in ("loadedOutput", "loadedInput"):
        if isinstance(data.get(key), str):
            state[key] = data[key]
    return state


def state_changed(a: dict, b: dict) -> bool:
    return a != b


# ───────────────────────────── presets ─────────────────────────────


def output_preset(gains: list[float], preamp: float) -> dict:
    def channel():
        return {
            f"band{i}": {
                "frequency": float(freq),
                "gain": round(float(gain), 1),
                "q": 1.5,
                "type": "Bell",
                "mode": "RLC (BT)",
                "slope": "x1",
                "mute": False,
                "solo": False,
                "width": 4.0,
            }
            for i, (freq, gain) in enumerate(zip(FREQS, gains))
        }

    equalizer = {
        "bypass": False,
        "input-gain": round(float(preamp), 1),
        "output-gain": 0.0,
        "num-bands": 10,
        "mode": "IIR",
        "split-channels": False,
        "left": channel(),
        "right": channel(),
    }
    return {
        "output": {
            "blocklist": [],
            "plugins_order": ["equalizer#0"],
            "equalizer#0": equalizer,
        }
    }


def input_preset(active: bool, wet: float = 0.0) -> dict:
    return {
        "input": {
            "blocklist": [],
            "plugins_order": ["rnnoise#0"],
            "rnnoise#0": {
                "bypass": not active,
                "input-gain": 0.0,
                "output-gain": 0.0,
                "model": "Standard",
                "release": 0.0,
                "vad-thres": 50.0,
                "wet": wet,
            },
        }
    }


def write_output(gains: list[float], preamp: float) -> Path:
    path = OUT_DIR / f"{STUDIO_PRESET}.json"
    write_json(path, output_preset(gains, preamp))
    return path


def write_mic(active: bool) -> Path:
    path = IN_DIR / f"{MIC_ON_PRESET if active else MIC_OFF_PRESET}.json"
    write_json(path, input_preset(active))
    return path


def load_preset(name: str, chain: str = "output") -> str:
    ensure_engine()
    run_ee(["-l", name])
    time.sleep(0.25)
    loaded = preset_name(run_ee(["-a", chain]).stdout)
    if loaded != name:
        raise RuntimeError(f"EasyEffects did not load {chain} preset '{name}'")
    return loaded


def parse_preset_gains(path: Path) -> tuple[list[float], float] | None:
    """Map an arbitrary EasyEffects output preset onto our 10 fixed bands."""
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None
    output = data.get("output") if isinstance(data, dict) else None
    if not isinstance(output, dict):
        return None

    equalizer = None
    for key, value in output.items():
        if key.startswith("equalizer") and isinstance(value, dict):
            equalizer = value
            break
    if equalizer is None:
        return ([0.0] * 10, 0.0)

    bands: list[tuple[float, float]] = []
    for side in ("left", "right"):
        channel = equalizer.get(side)
        if not isinstance(channel, dict):
            continue
        for band in channel.values():
            if not isinstance(band, dict):
                continue
            try:
                bands.append((float(band["frequency"]), float(band["gain"])))
            except (KeyError, TypeError, ValueError):
                continue
        if bands:
            break

    gains: list[float] = []
    for freq in FREQS:
        if not bands:
            gains.append(0.0)
            continue
        nearest = min(bands, key=lambda b: abs(math.log(max(b[0], 1.0) / freq)))
        # gap of ~2/3 octave: do not invent a band that the preset does not have
        if abs(math.log(max(nearest[0], 1.0) / freq)) <= math.log(1.65):
            gains.append(round(clamp(nearest[1]), 1))
        else:
            gains.append(0.0)

    try:
        preamp = round(clamp(float(equalizer.get("input-gain", 0.0))), 1)
    except (TypeError, ValueError):
        preamp = 0.0
    return gains, preamp


def list_output_presets() -> list[dict]:
    names: list[str] = []
    try:
        names = sorted((p.stem for p in OUT_DIR.glob("*.json") if p.is_file()), key=str.casefold)
    except OSError:
        names = []
    result = [{"name": name, "builtin": True} for name in BUILTINS]
    for name in names:
        if name in GENERATED:
            continue
        result.append({"name": name, "builtin": False})
    return result


# ───────────────────────────── status ─────────────────────────────


def status() -> dict:
    state = read_state()
    binary = ee_bin()
    installed = binary is not None
    running = installed and is_running()

    loaded_output = ""
    loaded_input = ""
    bypassed = False
    if running:
        try:
            loaded_output = preset_name(run_ee(["-a", "output"], timeout=4).stdout)
            loaded_input = preset_name(run_ee(["-a", "input"], timeout=4).stdout)
            raw_bypass = preset_name(run_ee(["-b", "3"], timeout=4).stdout)
            bypassed = raw_bypass == "1"
        except (subprocess.TimeoutExpired, OSError, RuntimeError):
            pass

    changed = False

    # Someone loaded another output preset (EasyEffects window, another tool):
    # adopt it so the surface stays truthful.
    if loaded_output and loaded_output != state["loadedOutput"]:
        if loaded_output != STUDIO_PRESET:
            parsed = parse_preset_gains(OUT_DIR / f"{loaded_output}.json")
            if parsed is not None:
                state["gains"], state["preamp"] = parsed
                state["preset"] = loaded_output
        state["loadedOutput"] = loaded_output
        changed = True
    elif not loaded_output and state["loadedOutput"]:
        state["loadedOutput"] = ""
        changed = True

    if loaded_input and loaded_input != state["loadedInput"]:
        if loaded_input == MIC_ON_PRESET:
            state["mic"] = True
        elif loaded_input == MIC_OFF_PRESET:
            state["mic"] = False
        state["loadedInput"] = loaded_input
        changed = True
    elif not loaded_input and state["loadedInput"]:
        state["loadedInput"] = ""
        changed = True

    if changed:
        write_json(STATE_FILE, state)

    presets = list_output_presets()
    known = {p["name"] for p in presets}
    if state["preset"] not in known:
        presets.insert(0, {"name": state["preset"], "builtin": state["preset"] in BUILTINS})

    return {
        "ok": True,
        "installed": installed,
        "running": running,
        "bypassed": bypassed,
        "gains": state["gains"],
        "preamp": state["preamp"],
        "preset": state["preset"],
        "loadedOutput": loaded_output,
        "loadedInput": loaded_input,
        "mic": state["mic"],
        "presets": presets,
        "builtins": BUILTINS,
        "freqs": FREQS,
        "freqLabels": FREQ_LABELS,
        "generated": {
            "output": STUDIO_PRESET,
            "micOn": MIC_ON_PRESET,
            "micOff": MIC_OFF_PRESET,
        },
    }


# ───────────────────────────── commands ─────────────────────────────


def parse_gains(raw: str) -> list[float]:
    parts = [p.strip() for p in raw.split(",") if p.strip()]
    if len(parts) != 10:
        raise ValueError("expected 10 comma-separated gains")
    return [round(clamp(float(p)), 1) for p in parts]


def apply_eq(gains: list[float], preamp: float, preset: str) -> dict:
    gains = [round(clamp(g), 1) for g in gains]
    preamp = round(clamp(preamp), 1)
    write_output(gains, preamp)
    loaded = load_preset(STUDIO_PRESET, "output")
    state = read_state()
    state.update({
        "gains": gains,
        "preamp": preamp,
        "preset": preset,
        "loadedOutput": loaded,
    })
    write_json(STATE_FILE, state)
    return status()


def cmd_status(_args) -> dict:
    return status()


def cmd_eq(args) -> dict:
    state = read_state()
    gains = parse_gains(args.gains) if args.gains else state["gains"]
    preamp = state["preamp"] if args.preamp is None else float(args.preamp)
    return apply_eq(gains, preamp, args.preset or "Custom")


def cmd_preset(args) -> dict:
    name = args.name.strip()
    if not name:
        raise ValueError("preset name is empty")

    if name in BUILTINS:
        state = read_state()
        return apply_eq(list(BUILTINS[name]), state["preamp"], name)

    path = OUT_DIR / f"{name}.json"
    if not path.is_file():
        raise ValueError(f"preset not found: {name}")
    loaded = load_preset(name, "output")
    parsed = parse_preset_gains(path)
    state = read_state()
    if parsed is not None:
        state["gains"], state["preamp"] = parsed
    state["preset"] = name
    state["loadedOutput"] = loaded
    write_json(STATE_FILE, state)
    return status()


def cmd_bypass(args) -> dict:
    mode = args.mode
    if mode == "status":
        return status()
    if not ensure_engine():
        raise RuntimeError("EasyEffects is not running")
    current = preset_name(run_ee(["-b", "3"]).stdout) == "1"
    target = current if mode == "toggle" else (mode == "on")
    if mode == "toggle":
        target = not current
    run_ee(["-b", "1" if target else "2"])
    time.sleep(0.15)
    return status()


def cmd_mic(args) -> dict:
    mode = args.mode
    if mode == "status":
        return status()
    state = read_state()
    current = state["mic"]
    active = (not current) if mode == "toggle" else (mode == "on")
    if not ensure_engine():
        raise RuntimeError("EasyEffects is not running")
    write_mic(active)
    loaded = load_preset(MIC_ON_PRESET if active else MIC_OFF_PRESET, "input")
    state["mic"] = active
    state["loadedInput"] = loaded
    write_json(STATE_FILE, state)
    return status()


def cmd_reset(_args) -> dict:
    return apply_eq([0.0] * 10, 0.0, "Flat")


def cmd_start(_args) -> dict:
    if not ee_bin():
        raise RuntimeError("EasyEffects is not installed")
    ensure_engine()
    return status()


def cmd_stop(_args) -> dict:
    if ee_bin() and is_running():
        run_ee(["-q"], timeout=5)
        for _ in range(20):
            if not is_running():
                break
            time.sleep(0.1)
    return status()


def cmd_open(_args) -> dict:
    binary = ee_bin()
    if not binary:
        raise RuntimeError("EasyEffects is not installed")
    subprocess.Popen([binary], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                     start_new_session=True)
    time.sleep(0.4)
    return status()


def main() -> int:
    parser = argparse.ArgumentParser(description="Edots Audio Studio helper")
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("status", help="print JSON status").set_defaults(func=cmd_status)

    eq = sub.add_parser("eq", help="write and load the Edots Studio output preset")
    eq.add_argument("--gains", help="10 comma-separated dB values, low → high")
    eq.add_argument("--preamp", type=float, help="preamp in dB (-12..+12)")
    eq.add_argument("--preset", help="label saved in state")
    eq.set_defaults(func=cmd_eq)

    preset = sub.add_parser("preset", help="load a built-in or EasyEffects preset")
    preset.add_argument("name")
    preset.set_defaults(func=cmd_preset)

    bypass = sub.add_parser("bypass", help="global EasyEffects bypass")
    bypass.add_argument("mode", nargs="?", default="status", choices=["on", "off", "toggle", "status"])
    bypass.set_defaults(func=cmd_bypass)

    mic = sub.add_parser("mic", help="microphone RNNoise filter")
    mic.add_argument("mode", nargs="?", default="status", choices=["on", "off", "toggle", "status"])
    mic.set_defaults(func=cmd_mic)

    sub.add_parser("reset", help="flat EQ, zero preamp").set_defaults(func=cmd_reset)
    sub.add_parser("start", help="start EasyEffects in service mode").set_defaults(func=cmd_start)
    sub.add_parser("stop", help="quit EasyEffects").set_defaults(func=cmd_stop)
    sub.add_parser("open", help="open the EasyEffects window").set_defaults(func=cmd_open)

    args = parser.parse_args()
    try:
        result = args.func(args)
        print(json.dumps(result, ensure_ascii=False))
        return 0
    except Exception as exc:  # noqa: BLE001 — the UI needs a readable error
        print(json.dumps({"ok": False, "error": str(exc)}, ensure_ascii=False))
        return 1


if __name__ == "__main__":
    sys.exit(main())
