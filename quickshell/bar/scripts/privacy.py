#!/usr/bin/env python3
"""privacy.py — активні захоплення камери й мікрофона для «security pill» бару.

Джерела:
  • PipeWire (pw-dump -m) — усі застосунки, що пишуть звук або відео через
    PipeWire: Stream/Input/Audio та Stream/Input/Video у стані running/idle.
    Це дає назву застосунку й PID. Події приходять самі, без опитування.
  • inotify на /dev/video* — застосунки, що відкривають камеру напряму
    (ffmpeg, частина браузерів, libcamera). Подія лише будить скан /proc,
    тож у спокої демон нічого не опитує. Раз на 30 с — страхувальний скан
    (пропущене відкриття, якщо inotify недоступний).

Вивід — один JSON-рядок на зміну стану, щоб QML не тримав великий pw-dump:
  {"camera":[{"pid":123,"app":"Firefox","device":"C270 HD WEBCAM"}],
   "mic":[{"pid":456,"app":"Discord"}]}

Запускається з PrivacyService.qml. Сам нічого не записує на диск.
"""
import codecs
import ctypes
import glob
import json
import os
import select
import signal
import struct
import subprocess
import sys
import time

VIDEO_GLOB = "/dev/video*"

IN_OPEN = 0x00000020
IN_CLOSE_WRITE = 0x00000008
IN_CLOSE_NOWRITE = 0x00000010

# Фонові демони самого стека (v4l2-монітор WirePlumber пробує пристрої
# на старті / hotplug) — це не «застосунок користувача», крапку не показуємо.
IGNORED_CAMERA_APPS = {
    "pipewire", "wireplumber", "pipewire-media-session",
    "systemd-udevd", "udev-worker",
}

# Стани вузла PipeWire, які означають «застосунок тримає потік відкритим».
# suspended = потік є, але не під'єднаний; running/idle = реальне захоплення.
ACTIVE_STATES = {"running", "idle"}

SCAN_SAFETY_SEC = 30.0     # страхувальний скан /proc у спокої (inotify події зазвичай точніші)
SCAN_ACTIVE_SEC = 2.0      # доки камера відкрита — перевіряти, що вона ще відкрита
SCAN_FALLBACK_SEC = 2.0    # без inotify — частіше
WATCH_REFRESH_SEC = 5.0    # підхопити камеру, під'єднану після старту демона
EMIT_DEBOUNCE_SEC = 0.15   # pw-dump -m сипле кілька подій на один старт запису
OPEN_SETTLE_SEC = 0.25     # короткі проби пристроїв стеком не вважаємо захопленням


class Privacy:
    def __init__(self):
        self.stop = False
        # Quickshell не вбиває дочірні процеси при hot-reload — якщо батько
        # зник, демон має завершитись сам, інакше кожен reload лишає копію.
        self.parent_pid = os.getppid()
        self.nodes = {}                 # id -> PipeWire Node object
        self.camera_proc = []           # останній результат скану /proc
        self.last_scan = 0.0
        self.last_change = 0.0
        self.last_emit = None
        # inotify: скільки зараз відкритих /dev/video* (OPEN/CLOSE події).
        # Проби пристроїв самим стеком (PipeWire v4l2) — короткі відкриття,
        # тож поки лічильник не встоявся, /proc не скануємо.
        self.open_total = 0
        self.check_at = 0.0
        self.next_scan = 0.0
        self.next_refresh = 0.0
        self.pw = None
        self.pw_fd = -1
        self.pw_restart_at = 0.0
        self.pw_warned = False
        self.text_buf = ""
        self.decoder = json.JSONDecoder()
        self.utf8 = codecs.getincrementaldecoder("utf-8")("replace")
        self.inotify_fd = -1
        self._init_inotify()
        self._scan_camera(force=True)
        if self.camera_proc:
            self.open_total = 1   # камера вже була відкрита до старту демона

    # ── inotify ────────────────────────────────────────────────────────────
    def _init_inotify(self):
        try:
            libc = ctypes.CDLL("libc.so.6", use_errno=True)
            self._libc = libc
            fd = libc.inotify_init1(os.O_NONBLOCK | os.O_CLOEXEC)
            if fd < 0:
                return
            self.inotify_fd = fd
            if not self._refresh_watches():
                os.close(fd)
                self.inotify_fd = -1
        except Exception:
            self.inotify_fd = -1

    def _refresh_watches(self):
        """Додає нові /dev/video* (камеру могли під'єднати після старту)."""
        mask = IN_OPEN | IN_CLOSE_WRITE | IN_CLOSE_NOWRITE
        watched = 0
        for dev in sorted(glob.glob(VIDEO_GLOB)):
            if self._libc.inotify_add_watch(self.inotify_fd, dev.encode(), mask) >= 0:
                watched += 1
        return watched > 0

    def _drain_inotify(self):
        now = time.monotonic()
        try:
            while True:
                data = os.read(self.inotify_fd, 4096)
                if not data:
                    break
                # struct inotify_event { int wd; u32 mask; u32 cookie; u32 len; }
                off = 0
                while off + 16 <= len(data):
                    _, mask, _, ln = struct.unpack_from("iIII", data, off)
                    off += 16 + ln
                    if mask & IN_OPEN:
                        self.open_total += 1
                        self.check_at = now + OPEN_SETTLE_SEC
                    elif mask & (IN_CLOSE_WRITE | IN_CLOSE_NOWRITE):
                        self.open_total = max(0, self.open_total - 1)
        except BlockingIOError:
            pass
        except OSError:
            self.inotify_fd = -1

    # ── пряме відкриття /dev/video* ────────────────────────────────────────
    def _video_name(self, dev):
        name = os.path.basename(dev)
        try:
            with open("/sys/class/video4linux/%s/name" % name) as fh:
                return fh.read().strip()
        except OSError:
            return ""

    def _scan_camera(self, force=False):
        now = time.monotonic()
        if not force and now - self.last_scan < 0.05:
            return
        self.last_scan = now
        found = []
        try:
            pids = os.listdir("/proc")
        except OSError:
            pids = []
        for pid in pids:
            if not pid.isdigit():
                continue
            try:
                with open("/proc/%s/comm" % pid) as fh:
                    comm = fh.read().strip()
                fds = os.listdir("/proc/%s/fd" % pid)
            except OSError:
                continue
            if comm in IGNORED_CAMERA_APPS:
                continue
            devices = set()
            for fd in fds:
                try:
                    target = os.readlink("/proc/%s/fd/%s" % (pid, fd))
                except OSError:
                    continue
                if target.startswith("/dev/video"):
                    devices.add(target)
            if devices:
                names = sorted({(self._video_name(d) or os.path.basename(d)).split(":")[0].strip()
                                for d in devices})
                found.append({"pid": int(pid), "app": comm,
                              "device": ", ".join(names)})
        found.sort(key=lambda x: (x["app"].lower(), x["pid"]))
        if found != self.camera_proc:
            self.camera_proc = found
            self.last_change = now
        return found

    # ── PipeWire ───────────────────────────────────────────────────────────
    def _start_pw(self):
        try:
            self.pw = subprocess.Popen(
                ["pw-dump", "-m", "-N"],
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                bufsize=0,
            )
            self.pw_fd = self.pw.stdout.fileno()
            os.set_blocking(self.pw_fd, False)
            self.text_buf = ""
            self.utf8 = codecs.getincrementaldecoder("utf-8")("replace")
        except FileNotFoundError:
            self.pw = None
            self.pw_fd = -1
            if not self.pw_warned:
                print("privacy.py: pw-dump not found; camera-only mode", file=sys.stderr)
                self.pw_warned = True
            self.pw_restart_at = time.monotonic() + 60.0
        except OSError:
            self.pw = None
            self.pw_fd = -1
            self.pw_restart_at = time.monotonic() + 2.0

    def _stop_pw(self):
        if self.pw is not None:
            try:
                self.pw.terminate()
                self.pw.wait(timeout=1.0)
            except Exception:
                try:
                    self.pw.kill()
                except Exception:
                    pass
        self.pw = None
        self.pw_fd = -1
        # новий pw-dump почнеться з повного знімка; поки його нема, не тримаємо
        # «застряглі» активні потоки в UI
        if self.nodes:
            self.nodes.clear()
            self.last_change = time.monotonic()

    def _feed_pw(self, data):
        self.text_buf += self.utf8.decode(data)
        while True:
            s = self.text_buf.lstrip()
            if not s:
                self.text_buf = ""
                break
            # Не намагаємось розібрати обірваний JSON: інакше на старті
            # pw-dump -m віддає 400+ КБ кількома шматками, і кожен шматок
            # даремно сканується з нуля. Повний знімок приходить одним масивом.
            if s.rstrip()[-1:] not in ("]", "}"):
                self.text_buf = s
                break
            try:
                obj, end = self.decoder.raw_decode(s)
            except json.JSONDecodeError:
                self.text_buf = s
                break
            self.text_buf = s[end:]
            if isinstance(obj, list):
                self._apply_changes(obj)

    def _apply_changes(self, items):
        changed = False
        for item in items:
            if not isinstance(item, dict):
                continue
            oid = item.get("id")
            if oid is None:
                continue
            if item.get("info") is None:
                if self.nodes.pop(oid, None) is not None:
                    changed = True
                continue
            if "Node" not in str(item.get("type", "")):
                continue
            old = self.nodes.get(oid)
            self.nodes[oid] = item
            if old is None or self._capture_key(old) != self._capture_key(item):
                changed = True
        if changed:
            self.last_change = time.monotonic()

    def _capture_key(self, obj):
        info = obj.get("info") or {}
        props = info.get("props") or {}
        return (props.get("media.class"), info.get("state"),
                props.get("application.name"), props.get("application.process.id"),
                props.get("node.name"))

    def _pw_streams(self):
        streams = []
        for obj in self.nodes.values():
            info = obj.get("info") or {}
            props = info.get("props") or {}
            media_class = props.get("media.class") or ""
            if not media_class.startswith("Stream/Input/"):
                continue
            # .../Internal — це внутрішній бік пристрою (напр. Bluetooth),
            # а не окремий застосунок; дублювати його в пігулці не треба.
            if media_class.endswith("/Internal"):
                continue
            if (info.get("state") or "") not in ACTIVE_STATES:
                continue
            kind = "camera" if media_class.startswith("Stream/Input/Video") else "mic"
            pid = props.get("application.process.id")
            try:
                pid = int(pid) if pid is not None else 0
            except (TypeError, ValueError):
                pid = 0
            app = (props.get("application.name")
                   or props.get("application.process.binary")
                   or props.get("node.name") or "?")
            streams.append({"kind": kind, "pid": pid, "app": str(app)})
        return streams

    # ── знімок ─────────────────────────────────────────────────────────────
    def snapshot(self):
        camera = list(self.camera_proc)
        mic = []
        seen = set()
        for s in self._pw_streams():
            key = (s["kind"], s["pid"] or s["app"].lower())
            if key in seen:
                continue
            seen.add(key)
            if s["kind"] == "camera":
                camera.append({"pid": s["pid"], "app": s["app"]})
            else:
                mic.append({"pid": s["pid"], "app": s["app"]})
        # dedupe камери: застосунок міг потрапити і з /proc, і з PipeWire
        merged = {}
        for c in camera:
            key = c["pid"] or c["app"].lower()
            cur = merged.get(key)
            if cur is None:
                merged[key] = {"pid": c["pid"], "app": c["app"],
                               "device": c.get("device", "")}
            elif c.get("device") and not cur.get("device"):
                cur["device"] = c["device"]
        camera = sorted(merged.values(), key=lambda x: (x["app"].lower(), x["pid"]))
        mic.sort(key=lambda x: (x["app"].lower(), x["pid"]))
        return {"camera": camera, "mic": mic}

    def emit(self):
        snap = self.snapshot()
        if snap == self.last_emit:
            return
        self.last_emit = snap
        try:
            sys.stdout.write(json.dumps(snap, ensure_ascii=False,
                                        separators=(",", ":")) + "\n")
            sys.stdout.flush()
        except (BrokenPipeError, OSError):
            self.stop = True

    def run(self):
        self.emit()
        self._start_pw()
        while not self.stop:
            if os.getppid() != self.parent_pid:
                break
            now = time.monotonic()
            if self.pw is None and now >= self.pw_restart_at:
                self._start_pw()

            fds = []
            if self.pw_fd >= 0:
                fds.append(self.pw_fd)
            if self.inotify_fd >= 0:
                fds.append(self.inotify_fd)
            try:
                ready, _, _ = select.select(fds, [], [], 0.2)
            except InterruptedError:
                continue

            if self.pw_fd >= 0 and self.pw_fd in ready:
                try:
                    data = os.read(self.pw_fd, 65536)
                except BlockingIOError:
                    data = None
                except OSError:
                    data = b""
                if data:
                    self._feed_pw(data)
                elif data == b"":
                    self._stop_pw()
                    self.pw_restart_at = time.monotonic() + 2.0

            if self.inotify_fd >= 0 and self.inotify_fd in ready:
                self._drain_inotify()

            now = time.monotonic()
            if self.inotify_fd < 0:
                # без inotify лишається лише опитування
                if now - self.last_scan >= SCAN_FALLBACK_SEC:
                    self._scan_camera()
            else:
                if now >= self.next_refresh:
                    self._refresh_watches()
                    self.next_refresh = now + WATCH_REFRESH_SEC

                if self.open_total <= 0:
                    # застосунок закрив камеру — не чекаємо скану
                    if self.camera_proc:
                        self.camera_proc = []
                        self.last_change = now
                    if now - self.last_scan >= SCAN_SAFETY_SEC:
                        self._scan_camera()
                        if self.camera_proc:
                            self.open_total = 1
                            self.next_scan = now + SCAN_ACTIVE_SEC
                elif now >= self.check_at and now >= self.next_scan:
                    found = self._scan_camera(force=True)
                    self.next_scan = now + (SCAN_ACTIVE_SEC if found else SCAN_SAFETY_SEC)
                    # /proc — джерело істини: якщо там порожньо, лічильник
                    # «застряг» на пропущеній CLOSE-події
                    if not found:
                        self.open_total = 0

            if self.last_change and now - self.last_change >= EMIT_DEBOUNCE_SEC:
                self.emit()
                self.last_change = 0.0

    def on_signal(self, *_):
        self.stop = True

    def close(self):
        self._stop_pw()
        if self.inotify_fd >= 0:
            try:
                os.close(self.inotify_fd)
            except OSError:
                pass
            self.inotify_fd = -1


def main():
    app = Privacy()
    signal.signal(signal.SIGINT, app.on_signal)
    signal.signal(signal.SIGTERM, app.on_signal)
    try:
        app.run()
    finally:
        app.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
