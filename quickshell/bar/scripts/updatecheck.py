#!/usr/bin/env python3
"""updatecheck.py — non-locking update check for the Edots update centre.

Prints JSON:
  {"repo":[{name,old,new}], "aur":[...], "flatpak":[...],
   "error":"", "checked":<epoch>}
"""
import json
import re
import shutil
import subprocess
import sys
import time

ROW = re.compile(r"^(\S+)\s+(\S+)\s+->\s+(\S+)$")


def run(args, timeout=45):
    try:
        p = subprocess.run(args, capture_output=True, text=True, timeout=timeout)
        return p.returncode, p.stdout or "", p.stderr or ""
    except (OSError, subprocess.TimeoutExpired):
        return 1, "", ""


def rows_from_arrows(text):
    out = []
    for line in text.splitlines():
        m = ROW.match(line.strip())
        if m:
            out.append({"name": m.group(1), "old": m.group(2), "new": m.group(3)})
    return out


def arch_repo():
    if shutil.which("checkupdates"):
        _, out, _ = run(["checkupdates"])
        return rows_from_arrows(out)
    # pacman -Qu reads the sync database and does not take the lock.
    _, out, _ = run(["pacman", "-Qu"])
    return rows_from_arrows(out)


def arch_aur():
    for helper in ("yay", "paru"):
        if shutil.which(helper):
            _, out, _ = run([helper, "-Qum"], timeout=60)
            return rows_from_arrows(out)
    return []


def flatpak_rows():
    if not shutil.which("flatpak"):
        return []
    _, out, _ = run(["flatpak", "remote-ls", "--updates", "--columns=application,version"])
    out_rows = []
    for line in out.splitlines():
        parts = [p.strip() for p in line.split("\t")]
        if not parts or not parts[0]:
            continue
        out_rows.append({
            "name": parts[0],
            "old": "",
            "new": parts[1] if len(parts) > 1 else "",
        })
    return out_rows


def debian_rows():
    if not shutil.which("apt"):
        return []
    _, out, _ = run(["apt", "list", "--upgradable"])
    rows = []
    for line in out.splitlines():
        if "/" not in line or line.startswith("Listing"):
            continue
        name = line.split("/", 1)[0]
        new = line.split()[1] if len(line.split()) > 1 else ""
        old = ""
        m = re.search(r"upgradable from:\s*([^\]\s]+)", line)
        if m:
            old = m.group(1)
        rows.append({"name": name, "old": old, "new": new})
    return rows


def fedora_rows():
    if not shutil.which("dnf"):
        return []
    rc, out, _ = run(["dnf", "-q", "check-update"], timeout=90)
    if rc not in (0, 100):
        return []
    rows = []
    for line in out.splitlines():
        parts = line.split()
        if len(parts) >= 2 and "." in parts[0]:
            name = parts[0].rsplit(".", 1)[0]
            rows.append({"name": name, "old": "", "new": parts[1]})
    return rows


def main():
    repo, aur = [], []
    if shutil.which("pacman"):
        repo = arch_repo()
        aur = arch_aur()
    elif shutil.which("apt"):
        repo = debian_rows()
    elif shutil.which("dnf"):
        repo = fedora_rows()

    payload = {
        "repo": repo,
        "aur": aur,
        "flatpak": flatpak_rows(),
        "error": "",
        "checked": int(time.time()),
    }
    json.dump(payload, sys.stdout, ensure_ascii=False)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:  # never let the surface hang on a parser bug
        json.dump({"repo": [], "aur": [], "flatpak": [], "error": str(exc), "checked": int(time.time())},
                  sys.stdout)
        sys.stdout.write("\n")
        sys.exit(0)
