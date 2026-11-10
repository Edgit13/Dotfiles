#!/usr/bin/env python3
"""powerwatch — легкий семплер для меню живлення Edots (Quickshell).

Запускається лише поки відкрите меню живлення (PowerService), тому не витрачає
ресурси у фоні. Раз на секунду віддає один JSON-рядок:

  {"t":"snap","ts":…,"ncpu":8,"interval":1.0,"cpu":12.3,"ram":48.2,
   "ramUsed":7.4,"ramTotal":15.5,"temp":56,"load":0.84,"procs":312,
   "busyCpu":87.3,"top":[{"name":"firefox","n":14,"cpu":45.2,"mem":812.3}]}

  • cpu      — завантаження всієї машини, %
  • busyCpu  — сума CPU усіх процесів (100% = одне ядро)
  • top[].cpu — CPU групи (усі процеси з однаковим ім'ям), 100% = одне ядро
  • top[].mem — RSS групи, МБ

stdin: {"cmd":"quit"} — завершитись (або EOF).
"""
import json
import os
import select
import sys
import time
from glob import glob

CLK = os.sysconf("SC_CLK_TCK")
PAGE = os.sysconf("SC_PAGE_SIZE")
NCPU = os.cpu_count() or 1
MYPID = os.getpid()
INTERVAL = 1.0
TOP_N = 10

prev = {}          # pid -> (starttime, ticks)
prev_cpu = None    # (idle, total)
have_prev = False
temp_file = None


def low_priority():
    """Майже не заважає системі: nice 19 + SCHED_IDLE, як procwatch."""
    try:
        os.nice(19)
    except OSError:
        pass
    try:
        os.sched_setscheduler(0, os.SCHED_IDLE, os.sched_param(0))
    except (AttributeError, OSError):
        pass


def read_stat(pid):
    try:
        with open("/proc/%d/stat" % pid, "rb") as f:
            data = f.read()
    except OSError:
        return None
    lp, rp = data.find(b"("), data.rfind(b")")
    if lp < 0 or rp < 0:
        return None
    comm = data[lp + 1:rp].decode("utf-8", "replace")
    r = data[rp + 2:].split()
    if len(r) < 22:
        return None
    try:
        flags = int(r[6])
    except ValueError:
        return None
    if flags & 0x200000:           # kernel thread
        return None
    return {
        "comm": comm,
        "ticks": int(r[11]) + int(r[12]),
        "start": int(r[19]),
        "rss": int(r[21]) * PAGE,
    }


def read_cpu():
    try:
        with open("/proc/stat", "rb") as f:
            line = f.readline()
    except OSError:
        return None
    f = [int(x) for x in line.split()[1:]]
    if len(f) < 5:
        return None
    idle = f[3] + f[4]
    return idle, sum(f)


def read_mem():
    vals = {}
    try:
        with open("/proc/meminfo", "r") as f:
            for line in f:
                key, _, rest = line.partition(":")
                if key in ("MemTotal", "MemAvailable"):
                    vals[key] = int(rest.strip().split()[0])
    except (OSError, ValueError):
        return 0.0, 0.0, 0.0
    total = vals.get("MemTotal", 0)
    avail = vals.get("MemAvailable", 0)
    if total <= 0:
        return 0.0, 0.0, 0.0
    used = max(0, total - avail)
    return 100.0 * used / total, used / 1048576.0, total / 1048576.0


def find_temp_file():
    """coretemp → 'Package id 0', інакше будь-який coretemp, інакше thermal_zone."""
    global temp_file
    try:
        hwmons = os.listdir("/sys/class/hwmon")
    except OSError:
        hwmons = []
    fallback = None
    for h in hwmons:
        base = os.path.join("/sys/class/hwmon", h)
        try:
            with open(os.path.join(base, "name")) as f:
                if f.read().strip() != "coretemp":
                    continue
        except OSError:
            continue
        try:
            files = [x for x in os.listdir(base) if x.startswith("temp") and x.endswith("_input")]
        except OSError:
            files = []
        for name in sorted(files):
            label = name.replace("_input", "_label")
            try:
                with open(os.path.join(base, label)) as f:
                    if f.read().strip() == "Package id 0":
                        temp_file = os.path.join(base, name)
                        return
            except OSError:
                pass
        if files and fallback is None:
            fallback = os.path.join(base, sorted(files)[0])
    if fallback:
        temp_file = fallback
        return
    try:
        zones = os.listdir("/sys/class/thermal")
    except OSError:
        zones = []
    for z in sorted(zones):
        if not z.startswith("thermal_zone"):
            continue
        p = os.path.join("/sys/class/thermal", z, "temp")
        if os.path.isfile(p):
            temp_file = p
            return


def read_temp():
    global temp_file
    if temp_file is None:
        find_temp_file()
    if temp_file is None:
        return 0
    try:
        with open(temp_file, "r") as f:
            v = float(f.read().strip())
    except (OSError, ValueError):
        temp_file = None
        return 0
    return round(v / 1000.0) if v > 1000 else round(v)


def read_load():
    try:
        with open("/proc/loadavg", "r") as f:
            return float(f.read().split()[0])
    except (OSError, ValueError, IndexError):
        return 0.0


def _num(path):
    try:
        with open(path, "r") as f:
            return float(f.read().strip())
    except (OSError, ValueError):
        return 0.0


def read_battery():
    """Додаткові дані, яких немає в UPower: цикли та проєктна ємність (Wh)."""
    for base in sorted(glob("/sys/class/power_supply/BAT*")):
        if _num(os.path.join(base, "present")) == 0 and not os.path.exists(os.path.join(base, "capacity")):
            continue
        cycles = int(_num(os.path.join(base, "cycle_count")))
        vmin = _num(os.path.join(base, "voltage_min_design"))
        design = _num(os.path.join(base, "energy_full_design")) / 1e6
        full = _num(os.path.join(base, "energy_full")) / 1e6
        if design <= 0:
            charge = _num(os.path.join(base, "charge_full_design"))
            if charge > 0 and vmin > 0:
                design = charge * vmin / 1e12
        if full <= 0:
            charge = _num(os.path.join(base, "charge_full"))
            if charge > 0 and vmin > 0:
                full = charge * vmin / 1e12
        return {
            "name": os.path.basename(base),
            "cycles": cycles,
            "designWh": round(design, 2),
            "fullWh": round(full, 2),
        }
    return {}


def scan_procs():
    procs = {}
    try:
        pids = [int(n) for n in os.listdir("/proc") if n.isdigit()]
    except OSError:
        return procs
    for pid in pids:
        if pid == MYPID:
            continue
        s = read_stat(pid)
        if s is not None:
            procs[pid] = s
    return procs


def tick(dt):
    global prev_cpu, have_prev

    cur_cpu = read_cpu()
    machine = 0.0
    if have_prev and cur_cpu and prev_cpu and dt > 0:
        d_total = cur_cpu[1] - prev_cpu[1]
        d_idle = cur_cpu[0] - prev_cpu[0]
        if d_total > 0:
            machine = max(0.0, min(100.0, 100.0 * (1.0 - d_idle / d_total)))
    prev_cpu = cur_cpu
    have_prev = cur_cpu is not None

    ram_pct, ram_used, ram_total = read_mem()
    procs = scan_procs()

    groups = {}
    busy = 0.0
    seen = set()
    for pid, s in procs.items():
        seen.add(pid)
        p = prev.get(pid)
        cpu = 0.0
        if p and p[0] == s["start"] and dt > 0:
            cpu = max(0.0, (s["ticks"] - p[1]) / CLK / dt * 100.0)
        prev[pid] = (s["start"], s["ticks"])
        busy += cpu
        g = groups.get(s["comm"])
        if g is None:
            g = groups[s["comm"]] = {"name": s["comm"], "n": 0, "cpu": 0.0, "mem": 0.0}
        g["n"] += 1
        g["cpu"] += cpu
        g["mem"] += s["rss"] / 1048576.0

    for pid in [p for p in prev if p not in seen]:
        prev.pop(pid, None)

    items = sorted(groups.values(), key=lambda g: (-g["cpu"], -g["mem"]))
    top = [{
        "name": g["name"],
        "n": g["n"],
        "cpu": round(g["cpu"], 1),
        "mem": round(g["mem"], 1),
    } for g in items[:TOP_N]]

    return {
        "t": "snap",
        "ts": int(time.time()),
        "ncpu": NCPU,
        "interval": round(dt, 2),
        "cpu": round(machine, 1),
        "ram": round(ram_pct, 1),
        "ramUsed": round(ram_used, 2),
        "ramTotal": round(ram_total, 2),
        "temp": read_temp(),
        "load": round(read_load(), 2),
        "procs": len(procs),
        "busyCpu": round(busy, 1),
        "top": top,
        "battery": read_battery(),
    }


def emit(obj):
    sys.stdout.write(json.dumps(obj, separators=(",", ":")) + "\n")
    sys.stdout.flush()


def stdin_command(timeout):
    """Чекаємо timeout секунд; повертаємо True, якщо треба вийти."""
    try:
        r, _, _ = select.select([sys.stdin], [], [], timeout)
    except (OSError, ValueError):
        return True
    if not r:
        return False
    line = sys.stdin.readline()
    if not line:
        return True
    try:
        cmd = json.loads(line)
    except ValueError:
        return False
    return cmd.get("cmd") == "quit"


def main():
    low_priority()
    # Початковий знімок лише запам'ятовує лічильники; CPU з'явиться за секунду.
    emit(tick(0.0))
    last = time.monotonic()
    while True:
        if stdin_command(INTERVAL):
            break
        now = time.monotonic()
        dt = now - last
        last = now
        try:
            emit(tick(dt))
        except (OSError, ValueError) as e:
            sys.stderr.write("powerwatch: %s\n" % e)
            sys.stderr.flush()


if __name__ == "__main__":
    try:
        main()
    except (KeyboardInterrupt, BrokenPipeError):
        pass
