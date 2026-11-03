#!/usr/bin/env python3
"""procwatch — легкий монітор процесів для Edots (Quickshell).

Окремий процес (запускається з MonitorService), що майже не навантажує систему:
  • працює з найнижчим пріоритетом (nice 19 + SCHED_IDLE), читає лише /proc/<pid>/stat,
    опитує раз на N секунд (за замовчуванням 2; 1 — коли відкрито меню ресурсів);
  • рахує CPU/RAM по «групах» (uid + ім'я процесу: усі процеси firefox = одна група);
  • стежить за лімітами (глобальні, для Quickshell окремо, перевизначення по іменах);
  • при тривалому перевищенні — сповіщення з кнопками (Заморозити / У білий список / Ігнорувати);
  • тимчасове заморожування SIGSTOP → автоматичне розморожування SIGCONT (усе розморожується при виході);
  • для Quickshell: просить у шелла «режим розвантаження» (подія relief_*), бо замороження шелла = зависання UI.

Протокол (JSON по рядку):
  stdin  → {"cmd":"config",...} | {"cmd":"ui","fast":bool} | {"cmd":"freeze","key":"uid:name","secs":N}
           {"cmd":"thaw","key":..} | {"cmd":"thawall"} | {"cmd":"relief","active":bool} | {"cmd":"quit"}
  stdout ← {"t":"snap",...} кожен тік | {"t":"event","kind":...,...}
"""
import fnmatch
import json
import os
import queue
import select
import signal
import subprocess
import sys
import threading
import time

CLK = os.sysconf("SC_CLK_TCK")
NCPU = os.cpu_count() or 1
MYPID = os.getpid()
MYUID = os.getuid()
# Демона завжди запускає Quickshell (MonitorService) → батько і є шелл, незалежно від імені процесу.
# PROCWATCH_STANDALONE=1 — для ручного запуску/тестів (тоді шукаємо лише за іменем).
PARENT = 0 if os.environ.get("PROCWATCH_STANDALONE") else os.getppid()
RUNDIR = os.environ.get("XDG_RUNTIME_DIR") or "/tmp"
STATE_FILE = os.path.join(RUNDIR, "procwatch-frozen.json")
SHELL_NAMES = ("quickshell", "qs")

# Не чіпаємо, коли protectSystem увімкнено: без них сесія/звук/мережа/вхід перестануть працювати
BUILTIN_PROTECTED = [
    "systemd*", "init", "dbus*", "*polkit*", "pipewire*", "wireplumber", "pulseaudio", "NetworkManager",
    "Xwayland", "Xorg", "mango*", "sway", "Hyprland", "kwin*", "gnome-shell", "sddm*", "gdm*", "lightdm",
    "login", "agetty", "udevd", "swaync", "gamemoded", "upowerd", "bluetoothd", "wpa_supplicant", "pam-auth*",
    "swaylock*", "swayidle", "rtkit-daemon", "polkitd", "(sd-pam)",
]

MSG = {
    "uk": {
        "title_over": "{name} навантажує систему",
        "body_cpu": "CPU {cpu:.0f}% (ліміт {limit:.0f}%) вже {secs} с.",
        "body_mem": "Пам'ять {mem:.0f} МБ (ліміт {limit:.0f} МБ) вже {secs} с.",
        "a_freeze": "Заморозити на {secs} с",
        "a_wl": "У білий список",
        "a_ignore": "Ігнорувати",
        "title_frozen": "{name} заморожено",
        "body_frozen": "Автоматично розморожу через {secs} с.",
        "title_thawed": "{name} розморожено",
        "body_thawed": "Процес знову працює.",
        "title_shell": "Quickshell навантажує систему",
        "body_shell": "CPU {cpu:.0f}%, пам'ять {mem:.0f} МБ. Знизити навантаження на {mins} хв (без ефектів і важких віджетів)?",
        "a_relief": "Так, на {mins} хв",
        "a_no": "Ні",
    },
    "en": {
        "title_over": "{name} is loading the system",
        "body_cpu": "CPU {cpu:.0f}% (limit {limit:.0f}%) for {secs}s.",
        "body_mem": "Memory {mem:.0f} MB (limit {limit:.0f} MB) for {secs}s.",
        "a_freeze": "Freeze for {secs}s",
        "a_wl": "Whitelist",
        "a_ignore": "Ignore",
        "title_frozen": "{name} frozen",
        "body_frozen": "It will be resumed automatically in {secs}s.",
        "title_thawed": "{name} resumed",
        "body_thawed": "The process is running again.",
        "title_shell": "Quickshell is loading the system",
        "body_shell": "CPU {cpu:.0f}%, memory {mem:.0f} MB. Reduce load for {mins} min (no effects, heavy widgets hidden)?",
        "a_relief": "Yes, for {mins} min",
        "a_no": "No",
    },
}

cfg = {
    "scope": "shell", "interval": 2.0,
    "cpuLimit": 90.0, "memLimit": 0.0, "sustain": 15,
    "shellCpuLimit": 25.0, "shellMemLimit": 0.0,
    "notify": True, "cooldown": 180, "action": "ask", "freezeSeconds": 30,
    "protectSystem": True, "whitelist": "", "overrides": "",
    "paused": False, "reliefEnabled": True, "reliefAsk": True, "reliefMinutes": 10,
    "lang": "uk",
}

ui_fast = False
relief_active = False
relief_hold_until = 0.0
running = True
actions_q = queue.Queue()
out_lock = threading.Lock()

prev = {}          # pid -> (starttime, ticks)
meta = {}          # pid -> (uid,)
over_since = {}    # key -> first time over limit
last_notified = {} # key -> time
ignored_until = {} # key -> time
frozen = {}        # key -> {"pids": {pid: starttime}, "until": ts, "name": str}
tick_no = 0
self_prev = None
last_groups = {}


def emit(obj):
    with out_lock:
        sys.stdout.write(json.dumps(obj, separators=(",", ":")) + "\n")
        sys.stdout.flush()


def tr(key, **kw):
    return MSG.get(cfg["lang"], MSG["en"])[key].format(**kw)


# ───────────────────────── /proc ─────────────────────────
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
    return {
        "comm": comm, "state": r[0].decode(), "ppid": int(r[1]), "flags": int(r[6]),
        "ticks": int(r[11]) + int(r[12]), "threads": int(r[17]), "start": int(r[19]),
        "rss": int(r[21]) * os.sysconf("SC_PAGE_SIZE"),
    }


def uid_of(pid):
    m = meta.get(pid)
    if m is None:
        try:
            m = (os.stat("/proc/%d" % pid).st_uid,)
        except OSError:
            m = (-1,)
        meta[pid] = m
    return m[0]


def matches(name, patterns):
    n = name.lower()
    for p in patterns:
        p = p.strip().lower()
        if p and (fnmatch.fnmatch(n, p) or n == p):
            return True
    return False


def is_protected(name):
    if cfg["protectSystem"] and matches(name, BUILTIN_PROTECTED):
        return True
    return matches(name, cfg["whitelist"].split(","))


def parse_overrides():
    out = {}
    for part in cfg["overrides"].split(","):
        bits = [b.strip() for b in part.split(":")]
        if len(bits) >= 2 and bits[0]:
            try:
                cpu = float(bits[1]) if bits[1] else None
                mem = float(bits[2]) if len(bits) > 2 and bits[2] else None
            except ValueError:
                continue
            out[bits[0].lower()] = (cpu, mem)
    return out


# ───────────────────────── freeze ─────────────────────────
def save_state():
    try:
        with open(STATE_FILE, "w") as f:
            json.dump({k: {"pids": v["pids"], "name": v["name"]} for k, v in frozen.items()}, f)
    except OSError:
        pass


def alive_same(pid, start):
    st = read_stat(pid)
    return st is not None and st["start"] == start


def do_freeze(key, name, pids, secs):
    done = {}
    for pid, start in pids.items():
        if uid_of(pid) != MYUID or not alive_same(pid, start):
            continue
        try:
            os.kill(pid, signal.SIGSTOP)
            done[pid] = start
        except OSError:
            pass
    if not done:
        return False
    frozen[key] = {"pids": done, "until": time.time() + secs, "name": name}
    save_state()
    emit({"t": "event", "kind": "frozen", "key": key, "name": name, "secs": secs})
    return True


def do_thaw(key, notify=True):
    f = frozen.pop(key, None)
    if not f:
        return
    for pid, start in f["pids"].items():
        if alive_same(pid, start):
            try:
                os.kill(pid, signal.SIGCONT)
            except OSError:
                pass
    save_state()
    emit({"t": "event", "kind": "thawed", "key": key, "name": f["name"]})
    if notify and cfg["notify"]:
        notify_async(tr("title_thawed", name=f["name"]), tr("body_thawed"), [], None)


def thaw_all():
    for k in list(frozen):
        do_thaw(k, notify=False)


def recover_leftovers():
    """Якщо попередній процес помер із замороженими — розморозити."""
    try:
        with open(STATE_FILE) as f:
            old = json.load(f)
    except (OSError, ValueError):
        return
    for v in old.values():
        for pid, start in (v.get("pids") or {}).items():
            try:
                pid = int(pid)
                if alive_same(pid, start):
                    os.kill(pid, signal.SIGCONT)
            except (OSError, ValueError):
                pass
    try:
        os.remove(STATE_FILE)
    except OSError:
        pass


# ───────────────────────── notifications ─────────────────────────
def notify_async(title, body, actions, ctx):
    """actions: [(key, label)]; результат (ctx, key) потрапляє в actions_q."""
    def worker():
        cmd = ["notify-send", "-a", "Edots Monitor", "-i", "utilities-system-monitor", "-u", "normal"]
        if actions:
            cmd += ["-t", "25000"]
            for k, label in actions:
                cmd += ["-A", "%s=%s" % (k, label)]
        cmd += [title, body]
        try:
            r = subprocess.run(cmd, capture_output=True, text=True, timeout=40)
            if actions and r.returncode != 0:  # старий libnotify без -A → просте сповіщення
                subprocess.run(["notify-send", "-a", "Edots Monitor", title, body], timeout=10)
                return
            choice = (r.stdout or "").strip()
            if choice and ctx is not None:
                actions_q.put((ctx, choice))
        except (OSError, subprocess.SubprocessError):
            pass
    threading.Thread(target=worker, daemon=True).start()


# ───────────────────────── тік ─────────────────────────
def shell_roots(procs):
    roots = {p for p, s in procs.items() if s["comm"] in SHELL_NAMES and uid_of(p) == MYUID}
    if PARENT > 1 and PARENT in procs and uid_of(PARENT) == MYUID:
        roots.add(PARENT)
    return roots


def tick(dt):
    global tick_no, self_prev, last_groups
    tick_no += 1
    now = time.time()
    procs = {}
    try:
        names = [int(n) for n in os.listdir("/proc") if n.isdigit()]
    except OSError:
        return
    for pid in names:
        st = read_stat(pid)
        if st is None or (st["flags"] & 0x200000):  # kernel thread
            continue
        procs[pid] = st

    roots = shell_roots(procs)
    shell_set = set(roots)
    if roots:  # нащадки Quickshell
        changed = True
        while changed:
            changed = False
            for pid, s in procs.items():
                if pid not in shell_set and s["ppid"] in shell_set:
                    shell_set.add(pid)
                    changed = True

    seen = set()
    groups = {}
    ov = parse_overrides()
    for pid, s in procs.items():
        seen.add(pid)
        p = prev.get(pid)
        cpu = 0.0
        if p and p[0] == s["start"] and dt > 0:
            cpu = (s["ticks"] - p[1]) / CLK / dt * 100.0
        prev[pid] = (s["start"], s["ticks"])
        s["cpu"] = max(0.0, cpu)
        uid = uid_of(pid)
        if pid == MYPID:          # сам монітор у списку не показуємо (його витрати — окремо в "self")
            continue
        if cfg["scope"] == "shell" and pid not in shell_set:
            continue
        key = "%d:%s" % (uid, s["comm"])
        g = groups.get(key)
        if g is None:
            g = groups[key] = {"key": key, "name": s["comm"], "uid": uid, "cpu": 0.0, "mem": 0.0, "pids": {},
                               "state": s["state"], "shell": False}
        g["cpu"] += s["cpu"]
        g["mem"] += s["rss"] / 1048576.0
        g["pids"][pid] = s["start"]
        if s["state"] == "T":
            g["state"] = "T"
        if pid in shell_set:
            g["shell"] = True
    for pid in [p for p in prev if p not in seen]:
        prev.pop(pid, None)
        meta.pop(pid, None)

    last_groups = groups

    # ── авто-розморожування ──
    for k in [k for k, f in frozen.items() if f["until"] <= now]:
        do_thaw(k)

    # ── ліміти ──
    for g in groups.values():
        name, key = g["name"], g["key"]
        is_shell = g["shell"] and (name in SHELL_NAMES or any(p in roots for p in g["pids"]))
        g["prot"] = is_protected(name) or is_shell
        g["frozen"] = key in frozen
        g["canFreeze"] = (g["uid"] == MYUID) and not g["prot"]
        cpu_lim, mem_lim = (cfg["shellCpuLimit"], cfg["shellMemLimit"]) if is_shell else (cfg["cpuLimit"], cfg["memLimit"])
        o = ov.get(name.lower())
        if o:
            if o[0] is not None:
                cpu_lim = o[0]
            if o[1] is not None:
                mem_lim = o[1]
        g["limit"] = cpu_lim
        g["memLimit"] = mem_lim
        over_cpu = cpu_lim > 0 and g["cpu"] > cpu_lim
        over_mem = mem_lim > 0 and g["mem"] > mem_lim
        g["over"] = bool(over_cpu or over_mem)
        if g["over"] and not g["frozen"]:
            over_since.setdefault(key, now)
        else:
            over_since.pop(key, None)
            continue
        secs = int(now - over_since[key])
        if secs < cfg["sustain"] or cfg["paused"]:
            continue
        if ignored_until.get(key, 0) > now or now - last_notified.get(key, 0) < cfg["cooldown"]:
            continue
        if g["prot"] and not is_shell:
            continue
        last_notified[key] = now
        emit({"t": "event", "kind": "exceed", "key": key, "name": name, "cpu": round(g["cpu"], 1),
              "mem": round(g["mem"]), "secs": secs})
        if is_shell:
            handle_shell_exceed(g)
        else:
            handle_exceed(g, over_cpu, secs)

    # ── знімок ──
    items = sorted(groups.values(), key=lambda g: (-g["cpu"], -g["mem"]))
    top = items[:25]
    inc = {g["key"] for g in top}
    top += [g for g in items[25:] if g["frozen"] or g["over"] and g["key"] not in inc]
    shell_info = None
    sg = next((g for g in groups.values() if any(p in roots for p in g["pids"])), None)
    if roots:
        shell_info = shell_breakdown(procs, roots, shell_set, sg)
    me = procs.get(MYPID)
    self_cpu = 0.0
    if me:
        ticks = me["ticks"]
        if self_prev is not None and dt > 0:
            self_cpu = (ticks - self_prev) / CLK / dt * 100.0
        self_prev = ticks
    emit({
        "t": "snap", "ts": int(now), "ncpu": NCPU, "scope": cfg["scope"], "interval": dt,
        "self": {"cpu": round(self_cpu, 2), "mem": round(me["rss"] / 1048576.0, 1) if me else 0},
        "shell": shell_info,
        "frozen": [{"key": k, "name": f["name"], "left": max(0, int(f["until"] - now))} for k, f in frozen.items()],
        "top": [{"key": g["key"], "name": g["name"], "n": len(g["pids"]), "cpu": round(g["cpu"], 1),
                 "mem": round(g["mem"]), "state": g["state"], "frozen": g["frozen"], "prot": g["prot"],
                 "over": g["over"], "limit": g["limit"], "memLimit": g["memLimit"], "canFreeze": g["canFreeze"]}
                for g in top],
    })


def shell_breakdown(procs, roots, shell_set, sg):
    info = {"cpu": 0.0, "mem": 0.0, "threads": [], "children": []}
    for pid in roots:
        s = procs[pid]
        info["cpu"] += s["cpu"]
        info["mem"] += s["rss"] / 1048576.0
        info["pid"] = pid
    info["cpu"] = round(info["cpu"], 1)
    info["mem"] = round(info["mem"])
    # потоки (main thread = логіка QML усіх компонентів; QSGRenderThread = рендер вікон)
    if ui_fast or tick_no % 5 == 0:
        th = []
        for pid in roots:
            try:
                for tid in os.listdir("/proc/%d/task" % pid):
                    t = read_stat_task(pid, int(tid))
                    if t:
                        th.append(t)
            except OSError:
                pass
        th.sort(key=lambda t: -t["cpu"])
        info["threads"] = [{"n": t["comm"], "cpu": round(t["cpu"], 1)} for t in th[:8]]
        global _last_threads
        _last_threads = info["threads"]
    else:
        info["threads"] = _last_threads
    kids = {}
    for pid in shell_set - roots:
        s = procs[pid]
        k = kids.setdefault(s["comm"], 0.0)
        kids[s["comm"]] = k + s["cpu"]
    info["children"] = [{"n": n, "cpu": round(c, 1)} for n, c in sorted(kids.items(), key=lambda x: -x[1])[:6]]
    return info


_last_threads = []
_thr_prev = {}


def read_stat_task(pid, tid):
    try:
        with open("/proc/%d/task/%d/stat" % (pid, tid), "rb") as f:
            data = f.read()
    except OSError:
        return None
    lp, rp = data.find(b"("), data.rfind(b")")
    r = data[rp + 2:].split()
    if len(r) < 20:
        return None
    ticks = int(r[11]) + int(r[12])
    start = int(r[19])
    now = time.monotonic()
    p = _thr_prev.get((pid, tid))
    _thr_prev[(pid, tid)] = (start, ticks, now)
    cpu = 0.0
    if p and p[0] == start and now > p[2]:
        cpu = (ticks - p[1]) / CLK / (now - p[2]) * 100.0
    return {"comm": data[lp + 1:rp].decode("utf-8", "replace"), "cpu": max(0.0, cpu)}


# ───────────────────────── реакції ─────────────────────────
def handle_exceed(g, over_cpu, secs):
    name, key = g["name"], g["key"]
    if cfg["paused"]:
        return
    freeze_secs = int(cfg["freezeSeconds"])
    if cfg["action"] == "freeze" and g["canFreeze"]:
        if do_freeze(key, name, g["pids"], freeze_secs) and cfg["notify"]:
            notify_async(tr("title_frozen", name=name), tr("body_frozen", secs=freeze_secs), [], None)
        return
    if not cfg["notify"]:
        return
    body = tr("body_cpu", cpu=g["cpu"], limit=g["limit"], secs=secs) if over_cpu \
        else tr("body_mem", mem=g["mem"], limit=g["memLimit"], secs=secs)
    acts = []
    if cfg["action"] != "none" and g["canFreeze"]:
        acts.append(("freeze", tr("a_freeze", secs=freeze_secs)))
    if g["uid"] == MYUID:
        acts.append(("wl", tr("a_wl")))
    acts.append(("ignore", tr("a_ignore")))
    notify_async(tr("title_over", name=name), body, acts, {"kind": "exceed", "key": key, "name": name,
                                                          "pids": dict(g["pids"])})


def handle_shell_exceed(g):
    if not cfg["reliefEnabled"] or relief_active or time.time() < relief_hold_until:
        return
    mins = int(cfg["reliefMinutes"])
    if not cfg["reliefAsk"]:
        emit({"t": "event", "kind": "relief", "minutes": mins, "auto": True})
        return
    if not cfg["notify"]:
        emit({"t": "event", "kind": "relief_suggest", "minutes": mins})
        return
    notify_async(tr("title_shell"), tr("body_shell", cpu=g["cpu"], mem=g["mem"], mins=mins),
                 [("relief", tr("a_relief", mins=mins)), ("no", tr("a_no"))], {"kind": "shell"})


def process_actions():
    while True:
        try:
            ctx, choice = actions_q.get_nowait()
        except queue.Empty:
            return
        if ctx["kind"] == "shell":
            if choice == "relief":
                emit({"t": "event", "kind": "relief", "minutes": int(cfg["reliefMinutes"]), "auto": False})
            continue
        key = ctx["key"]
        if choice == "freeze":
            secs = int(cfg["freezeSeconds"])
            if do_freeze(key, ctx["name"], ctx["pids"], secs):
                notify_async(tr("title_frozen", name=ctx["name"]), tr("body_frozen", secs=secs), [], None)
        elif choice == "wl":
            emit({"t": "event", "kind": "whitelist", "name": ctx["name"]})
        elif choice == "ignore":
            ignored_until[key] = time.time() + 3600


# ───────────────────────── команди ─────────────────────────
def handle_cmd(line):
    global ui_fast, relief_active, relief_hold_until, running
    try:
        c = json.loads(line)
    except ValueError:
        return
    cmd = c.get("cmd")
    if cmd == "config":
        for k, v in c.items():
            if k != "cmd" and k in cfg:
                cfg[k] = type(cfg[k])(v) if not isinstance(cfg[k], bool) else bool(v)
        cfg["interval"] = max(0.5, min(30.0, float(cfg["interval"])))
    elif cmd == "ui":
        ui_fast = bool(c.get("fast"))
    elif cmd == "freeze":
        key = c.get("key", "")
        g = last_groups.get(key)
        if g and g["canFreeze"]:
            do_freeze(key, g["name"], g["pids"], int(c.get("secs") or cfg["freezeSeconds"]))
    elif cmd == "thaw":
        do_thaw(c.get("key", ""), notify=False)
    elif cmd == "thawall":
        thaw_all()
    elif cmd == "relief":
        was = relief_active
        relief_active = bool(c.get("active"))
        if was and not relief_active:
            relief_hold_until = time.time() + 120  # не просити знову одразу після завершення
    elif cmd == "quit":
        running = False


def cleanup(*_):
    global running
    running = False


def main():
    try:
        os.nice(19)
    except OSError:
        pass
    try:
        os.sched_setscheduler(0, os.SCHED_IDLE, os.sched_param(0))
    except (OSError, AttributeError):
        pass
    signal.signal(signal.SIGTERM, cleanup)
    signal.signal(signal.SIGINT, cleanup)
    signal.signal(signal.SIGHUP, cleanup)
    recover_leftovers()
    emit({"t": "event", "kind": "ready", "pid": MYPID, "ncpu": NCPU})

    last = time.monotonic()
    nxt = last
    # перший тік лише прогріває лічильники (cpu = 0)
    while running:
        timeout = max(0.0, nxt - time.monotonic())
        try:
            r, _, _ = select.select([sys.stdin], [], [], timeout)
        except (InterruptedError, ValueError):
            continue
        if r:
            line = sys.stdin.readline()
            if line == "":
                break  # шелл закрився
            handle_cmd(line)
        process_actions()
        t = time.monotonic()
        if t >= nxt:
            dt = t - last
            last = t
            tick(dt)
            nxt = t + (1.0 if ui_fast else cfg["interval"])
    thaw_all()
    try:
        os.remove(STATE_FILE)
    except OSError:
        pass


if __name__ == "__main__":
    main()
