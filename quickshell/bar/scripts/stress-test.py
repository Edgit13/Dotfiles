#!/usr/bin/env python3
"""stress-test — навантажувач для перевірки монітора процесів (Settings → Монітор).

  ./stress-test.py                       # ~80% CPU усієї системи + до 50% RAM, 60 с
  ./stress-test.py --cpu 80 --ram 50 --time 120
  ./stress-test.py --cpu 100 --ram 0     # лише CPU
  Ctrl-C — зупинити достроково (пам'ять звільняється одразу).

Процес називається «edots-stress» (видно у вкладці Монітор). Щоб монітор спрацював швидко:
Налаштування → Монітор: Область = «Уся система», «Перевищення триває» = 5 с, ліміт CPU, напр. 60.

Безпека: RAM-ціль обмежена так, щоб лишалось ≥ 1.5 ГБ (і ≥ 10%) вільної пам'яті — OOM-killer не прийде.
Лише стандартна бібліотека Python 3.
"""
import argparse
import ctypes
import multiprocessing as mp
import os
import signal
import sys
import time


def set_name(name):
    try:
        ctypes.CDLL("libc.so.6").prctl(15, name.encode()[:15], 0, 0, 0)  # PR_SET_NAME
    except OSError:
        pass


def meminfo():
    d = {}
    with open("/proc/meminfo") as f:
        for line in f:
            k, v = line.split(":")
            d[k] = int(v.split()[0]) * 1024
    return d


def cpu_worker(duty, stop):
    set_name("edots-stress")
    period = 0.1
    busy = period * duty
    while not stop.is_set():
        end = time.perf_counter() + busy
        while time.perf_counter() < end:
            pass
        rest = period - busy
        if rest > 0:
            time.sleep(rest)


def cpu_times():
    with open("/proc/stat") as f:
        v = [int(x) for x in f.readline().split()[1:]]
    idle = v[3] + (v[4] if len(v) > 4 else 0)
    return sum(v), idle


def main():
    ap = argparse.ArgumentParser(description="Навантажувач CPU/RAM для тесту монітора процесів")
    ap.add_argument("--cpu", type=float, default=80, help="цільове завантаження ВСІХ ядер, %% (за замовч. 80)")
    ap.add_argument("--ram", type=float, default=50, help="скільки %% ЗАГАЛЬНОЇ пам'яті зайняти (за замовч. 50)")
    ap.add_argument("--time", type=float, default=60, help="тривалість, с (за замовч. 60)")
    ap.add_argument("--ramp", type=float, default=5, help="за скільки секунд нарощувати пам'ять (за замовч. 5)")
    a = ap.parse_args()
    a.cpu = max(0.0, min(100.0, a.cpu))

    set_name("edots-stress")
    ncpu = os.cpu_count() or 1
    mi = meminfo()
    want = int(mi["MemTotal"] * max(0.0, min(90.0, a.ram)) / 100)
    spare = max(1.5 * 2**30, mi["MemTotal"] * 0.10)
    cap = max(0, int(mi["MemAvailable"] - spare))
    target = min(want, cap)
    print("CPU: %d ядер × %.0f%%  |  RAM: ціль %.1f ГБ (запит %.1f, доступно %.1f)  |  %.0f с"
          % (ncpu, a.cpu, target / 2**30, want / 2**30, mi["MemAvailable"] / 2**30, a.time))
    if target < want:
        print("  ⚠ RAM обмежено для безпеки (лишаю вільними ≥1.5 ГБ / 10%)")

    stop = mp.Event()
    procs = []
    if a.cpu > 0:
        for _ in range(ncpu):
            p = mp.Process(target=cpu_worker, args=(a.cpu / 100.0, stop), daemon=True)
            p.start()
            procs.append(p)

    def quit_(*_):
        stop.set()
    signal.signal(signal.SIGINT, quit_)
    signal.signal(signal.SIGTERM, quit_)

    chunks = []
    held = 0
    chunk = 32 * 2**20
    t0 = time.time()
    last_t, last_i = cpu_times()
    last_print = t0
    while not stop.is_set() and time.time() - t0 < a.time:
        # ── пам'ять: плавно нарощуємо й «торкаємось» сторінок (інакше ядро їх не виділить) ──
        should = int(target * min(1.0, (time.time() - t0) / max(0.1, a.ramp)))
        while held < should:
            b = bytearray(chunk)
            for i in range(0, chunk, 4096):
                b[i] = 1
            chunks.append(b)
            held += chunk
        time.sleep(0.25)
        now = time.time()
        if now - last_print >= 1.0:
            t, i = cpu_times()
            busy = 100.0 * (1 - (i - last_i) / max(1, t - last_t))
            last_t, last_i, last_print = t, i, now
            print("\r  %3.0f с  CPU системи %5.1f%%   RAM у нас %.2f ГБ   " % (now - t0, busy, held / 2**30), end="", flush=True)
    print("\nЗупиняю…")
    stop.set()
    for p in procs:
        p.join(timeout=2)
    chunks.clear()
    print("Готово — пам'ять звільнено.")


if __name__ == "__main__":
    main()
