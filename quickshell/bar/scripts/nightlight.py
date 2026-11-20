#!/usr/bin/env python3
"""nightlight.py — Edots night light.

Reads ~/.config/quickshell/nightlight.json (written by Settings) and applies
the colour temperature with gammastep.

gammastep must keep running to hold the wlroots gamma-control object: when the
process exits, the compositor restores the neutral ramp. We therefore manage a
single long-lived instance (pid file + a private -c marker so we only ever
touch our own processes) and restart it when the temperature changes.

  nightlight.py apply          apply the current config
  nightlight.py status         print the state file
  nightlight.py on|off|toggle  change enabled and apply
  nightlight.py temp 4000      set the manual temperature and apply
  nightlight.py mode manual|schedule
  nightlight.py reset          stop the daemon and restore neutral colour
"""
import datetime
import json
import os
import shutil
import signal
import subprocess
import sys
import time

CONF = os.path.expanduser("~/.config/quickshell/nightlight.json")
STATE = os.path.expanduser("~/.cache/quickshell/nightlight.state")
PID = os.path.expanduser("~/.cache/quickshell/nightlight.pid")
LOG = os.path.expanduser("~/.cache/quickshell/nightlight.log")
# Marker config file: its path ends up in the daemon cmdline, which lets us
# find (and only kill) instances started by this script.
MARK = os.path.expanduser("~/.cache/quickshell/nightlight-gammastep.conf")

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


def _argv(pid):
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as fh:
            raw = fh.read()
    except OSError:
        return []
    return [part.decode("utf-8", "replace") for part in raw.split(b"\0") if part]


def _cmdline(pid):
    return " ".join(_argv(pid))


def _scan(pattern):
    """Return pids whose cmdline contains pattern."""
    found = []
    try:
        entries = os.listdir("/proc")
    except OSError:
        return found
    for entry in entries:
        if not entry.isdigit() or int(entry) == os.getpid():
            continue
        if pattern in _cmdline(int(entry)):
            found.append(int(entry))
    return found


def _ours(pid):
    argv = _argv(pid)
    if not argv:
        return False
    # A real gammastep is the first argv entry; a wrapper script is interpreted
    # (`/bin/sh /path/to/gammastep ...`), so check the second entry too.
    heads = [os.path.basename(arg) for arg in argv[:2]]
    return "gammastep" in heads and MARK in argv


def _read_pid():
    try:
        with open(PID, encoding="utf-8") as fh:
            return int(fh.read().split()[0])
    except (OSError, ValueError, IndexError):
        return 0


def _running():
    """Return (pid, temp) of our live daemon, or (0, 0)."""
    pid = _read_pid()
    if not pid or not _ours(pid):
        return 0, 0
    try:
        with open(PID, encoding="utf-8") as fh:
            parts = fh.read().split()
        return pid, int(parts[1])
    except (OSError, ValueError, IndexError):
        return pid, 0


def _terminate(pid):
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    deadline = time.time() + 2.0
    while time.time() < deadline:
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            return
        time.sleep(0.05)
    try:
        os.kill(pid, signal.SIGKILL)
    except ProcessLookupError:
        pass


def stop():
    """Stop our daemon(s); the compositor resets the gamma ramp on exit."""
    pids = set(_scan(MARK))
    pid = _read_pid()
    if pid:
        pids.add(pid)
    for pid in pids:
        if _ours(pid):
            _terminate(pid)
    # Legacy leftovers from the previous script: `gammastep -x` (reset mode)
    # never exits and keeps the gamma-control object locked forever.
    for pid in _scan("gammastep"):
        argv = _argv(pid)
        if argv and os.path.basename(argv[0]) in ("sh", "dash", "bash"):
            argv = argv[1:]
        if (len(argv) == 2 and os.path.basename(argv[0]) == "gammastep"
                and argv[1] == "-x"):
            _terminate(pid)
    try:
        os.unlink(PID)
    except OSError:
        pass


def _read_log():
    try:
        with open(LOG, encoding="utf-8", errors="replace") as fh:
            return fh.read()
    except OSError:
        return ""


def start(temp):
    """(Re)start one gammastep instance for temp. Returns (ok, error)."""
    stop()
    os.makedirs(os.path.dirname(MARK), exist_ok=True)
    if not os.path.exists(MARK):
        with open(MARK, "w", encoding="utf-8") as fh:
            fh.write("[redshift]\n")

    try:
        with open(LOG, "w", encoding="utf-8") as log:
            proc = subprocess.Popen(
                ["gammastep", "-v", "-m", "wayland", "-c", MARK, "-O", str(temp)],
                stdin=subprocess.DEVNULL,
                stdout=log,
                stderr=subprocess.STDOUT,
                start_new_session=True,
                close_fds=True,
            )
    except OSError as exc:
        return False, f"gammastep failed to start: {exc}"

    with open(PID, "w", encoding="utf-8") as fh:
        fh.write(f"{proc.pid} {temp}\n")

    # Wait for either the "ready" notice or a failure report, so the UI can
    # show a real error instead of pretending the filter is active.
    deadline = time.time() + 1.5
    while time.time() < deadline:
        text = _read_log()
        if "do not support gamma adjustment" in text:
            stop()
            return False, "the compositor does not support gamma adjustment"
        if "Press ctrl-c to stop" in text:
            return True, ""
        if proc.poll() is not None:
            return False, "gammastep exited unexpectedly"
        time.sleep(0.05)

    # Slow start: keep the daemon, but do not claim success yet.
    if proc.poll() is not None:
        return False, "gammastep exited unexpectedly"
    return True, ""


def apply(cfg=None):
    cfg = cfg or load()
    mode = cfg.get("mode", "manual")

    if not cfg.get("enabled"):
        stop()
        save_state(False, NEUTRAL, mode)
        return 0

    if not shutil.which("gammastep"):
        save_state(True, NEUTRAL, mode, "gammastep is not installed")
        return 1

    temp = target_temp(cfg)
    pid, running_temp = _running()
    if pid and running_temp == temp:
        save_state(True, temp, mode)
        return 0

    ok, error = start(temp)
    if ok:
        save_state(True, temp, mode)
        return 0
    save_state(True, temp, mode, error)
    return 1


def main(argv):
    cmd = (argv[1] if len(argv) > 1 else "apply").lower()
    cfg = load()

    if cmd == "status":
        try:
            with open(STATE, encoding="utf-8") as fh:
                state = json.load(fh)
        except (OSError, ValueError):
            state = {
                "enabled": False,
                "temp": NEUTRAL,
                "mode": cfg.get("mode", "manual"),
                "error": "",
            }
        pid, running_temp = _running()
        if pid:
            state["enabled"] = True
            state["temp"] = running_temp
        elif state.get("enabled"):
            state["enabled"] = False
            state["temp"] = NEUTRAL
            state["error"] = state.get("error") or "gammastep is not running"
        print(json.dumps(state))
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
        stop()
        save_state(False, NEUTRAL, cfg.get("mode", "manual"))
        return 0

    print(f"unknown command: {cmd}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
