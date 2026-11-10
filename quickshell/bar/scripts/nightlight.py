#!/usr/bin/env python3
"""nightlight.py — Edots night light.

Reads ~/.config/quickshell/nightlight.json (written by Settings) and applies
the colour temperature with gammastep. One-shot: no long-running daemon.

  nightlight.py apply          apply the current config
  nightlight.py status         print the state file
  nightlight.py on|off|toggle  change enabled and apply
  nightlight.py temp 4000      set the manual temperature and apply
  nightlight.py mode manual|schedule
  nightlight.py reset          restore the neutral temperature
"""
import datetime
import json
import os
import shutil
import subprocess
import sys
import time

CONF = os.path.expanduser("~/.config/quickshell/nightlight.json")
STATE = os.path.expanduser("~/.cache/quickshell/nightlight.state")

DEFAULTS = {
    "enabled": False,
    "mode": "manual",
    "temp": 4000,
    "dayTemp": 6500,
    "nightTemp": 4000,
    "sunset": "19:00",
    "sunrise": "07:00",
}

NEUTRAL = 6500
RAMP = 60  # minutes of smooth transition around sunset / sunrise


def _clamp(v):
    try:
        return max(2000, min(6500, int(v)))
    except (TypeError, ValueError):
        return 4000


def load():
    data = dict(DEFAULTS)
    try:
        with open(CONF, encoding="utf-8") as fh:
            raw = json.load(fh)
        if isinstance(raw, dict):
            data.update(raw)
    except (OSError, ValueError):
        pass
    return data


def save(data):
    os.makedirs(os.path.dirname(CONF), exist_ok=True)
    with open(CONF, "w", encoding="utf-8") as fh:
        json.dump(data, fh, indent=2)
        fh.write("\n")


def save_state(enabled, temp, mode, error=""):
    os.makedirs(os.path.dirname(STATE), exist_ok=True)
    payload = {
        "enabled": bool(enabled),
        "temp": int(temp),
        "mode": mode,
        "error": error,
        "updated": int(time.time()),
    }
    with open(STATE, "w", encoding="utf-8") as fh:
        json.dump(payload, fh)
        fh.write("\n")


def _minutes(value):
    try:
        h, m = str(value).split(":", 1)
        return (int(h) % 24) * 60 + (int(m) % 60)
    except (ValueError, AttributeError):
        return None


def target_temp(cfg):
    if cfg.get("mode") != "schedule":
        return _clamp(cfg.get("temp", DEFAULTS["temp"]))

    now = datetime.datetime.now()
    cur = now.hour * 60 + now.minute
    sunrise = _minutes(cfg.get("sunrise", DEFAULTS["sunrise"]))
    sunset = _minutes(cfg.get("sunset", DEFAULTS["sunset"]))
    day = _clamp(cfg.get("dayTemp", DEFAULTS["dayTemp"]))
    night = _clamp(cfg.get("nightTemp", DEFAULTS["nightTemp"]))

    if sunrise is None or sunset is None or sunrise == sunset:
        return day if 7 * 60 <= cur < 19 * 60 else night

    # Normal case: sunrise < sunset. The "night" window wraps midnight.
    if sunrise < sunset:
        is_night = cur < sunrise or cur >= sunset
        since_sunset = (cur - sunset) % 1440
        until_sunrise = (sunrise - cur) % 1440
    else:
        is_night = sunset <= cur < sunrise
        since_sunset = (cur - sunset) % 1440
        until_sunrise = (sunrise - cur) % 1440

    if not is_night:
        return day

    # Smooth ramp down after sunset and up before sunrise.
    if since_sunset < RAMP and cur >= sunset:
        return int(day + (night - day) * since_sunset / RAMP)
    if until_sunrise <= RAMP:
        return int(night + (day - night) * (RAMP - until_sunrise) / RAMP)
    return night


def _gammastep(args):
    if not shutil.which("gammastep"):
        return 127
    try:
        return subprocess.run(
            ["gammastep", *args],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=8,
        ).returncode
    except (OSError, subprocess.TimeoutExpired):
        return 1


def apply(cfg=None):
    cfg = cfg or load()
    if not cfg.get("enabled"):
        rc = _gammastep(["-x"])
        if rc == 127:
            save_state(False, NEUTRAL, cfg.get("mode", "manual"), "gammastep is not installed")
            return 1
        save_state(False, NEUTRAL, cfg.get("mode", "manual"))
        return 0

    temp = target_temp(cfg)
    rc = _gammastep(["-O", str(temp)])
    if rc == 127:
        save_state(True, temp, cfg.get("mode", "manual"), "gammastep is not installed")
        return 1
    if rc != 0:
        save_state(True, temp, cfg.get("mode", "manual"), "gammastep failed")
        return 1
    save_state(True, temp, cfg.get("mode", "manual"))
    return 0


def main(argv):
    cmd = (argv[1] if len(argv) > 1 else "apply").lower()
    cfg = load()

    if cmd == "status":
        try:
            with open(STATE, encoding="utf-8") as fh:
                print(fh.read().strip())
        except OSError:
            print(json.dumps({"enabled": False, "temp": NEUTRAL, "mode": cfg.get("mode", "manual")}))
        return 0

    if cmd == "apply":
        return apply(cfg)

    if cmd in ("on", "off", "toggle"):
        cfg["enabled"] = (not cfg.get("enabled")) if cmd == "toggle" else (cmd == "on")
        save(cfg)
        return apply(cfg)

    if cmd == "temp":
        if len(argv) < 3:
            print("usage: nightlight.py temp <2000-6500>", file=sys.stderr)
            return 2
        cfg["temp"] = _clamp(argv[2])
        cfg["enabled"] = True
        cfg["mode"] = "manual"
        save(cfg)
        return apply(cfg)

    if cmd == "mode":
        if len(argv) < 3 or argv[2] not in ("manual", "schedule"):
            print("usage: nightlight.py mode manual|schedule", file=sys.stderr)
            return 2
        cfg["mode"] = argv[2]
        save(cfg)
        return apply(cfg)

    if cmd == "reset":
        cfg["enabled"] = False
        save(cfg)
        _gammastep(["-x"])
        save_state(False, NEUTRAL, cfg.get("mode", "manual"))
        return 0

    print(f"unknown command: {cmd}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
