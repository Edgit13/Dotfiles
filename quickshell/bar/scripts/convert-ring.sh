#!/usr/bin/env bash
#
# convert-ring.sh — кільце конвертації (SUPER + правий клік).
#
# Файлові менеджери не мають API «що виділено», тому питаємо їх як людину:
# надсилаємо Ctrl+C (wtype, інакше ydotool) і читаємо text/uri-list із
# кліпборда, після чого повертаємо кліпборд як був. Далі — JSON для шела й
# IPC convert open: кільце малює ConvertRing.qml.
#
# Поза файловим менеджером Ctrl+C не надсилаємо (щоб не вбити процес у
# терміналі) — беремо те, що вже є в кліпборді.
#
set -uo pipefail

QS="${EDOTS_QS:-qs}"
SHELL_QML="${EDOTS_SHELL:-$HOME/.config/quickshell/bar/shell.qml}"
PAYLOAD="${XDG_RUNTIME_DIR:-/tmp}/edots-convert.json"

# appid файлових менеджерів, де Ctrl+C копіює файли
FILE_MANAGERS=" org.gnome.Nautilus nautilus dolphin org.kde.dolphin Thunar thunar nemo Nemo pcmanfm caja io.github.lgse.Strata "

lang="$(jq -r '.language // "en"' "$HOME/.config/quickshell/general.json" 2>/dev/null || echo en)"
t() { if [ "$lang" = "uk" ]; then printf '%s' "$1"; else printf '%s' "$2"; fi; }

notify() {
    command -v notify-send >/dev/null 2>&1 || return 0
    notify-send -a Edots -i "$1" "$2" "${3:-}" >/dev/null 2>&1 || true
}
have() { command -v "$1" >/dev/null 2>&1; }

tmp="$(mktemp -d "${TMPDIR:-/tmp}/edots-convert.XXXXXX")" || exit 1
trap 'rm -rf "$tmp"' EXIT

appid="$(mmsg get focusing-client 2>/dev/null | sed -n 's/.*"appid":"\([^"]*\)".*/\1/p')"
cursor="$(mmsg get cursorpos 2>/dev/null)"

# кліпборд на потім (лише текст: картинки не чіпаємо)
saved=0
if have wl-paste && wl-paste --list-types 2>/dev/null | grep -qm1 '^text/'; then
    if wl-paste -n >"$tmp/clip" 2>/dev/null; then saved=1; fi
fi

# у файловому менеджері Ctrl+C копіює виділення
if [ -n "$appid" ] && printf '%s' "$FILE_MANAGERS" | grep -q " $appid "; then
    if have wtype; then
        wtype -M ctrl -k c -m ctrl 2>/dev/null
    elif have ydotool && pgrep -x ydotoold >/dev/null 2>&1; then
        ydotool key 29:1 46:1 46:0 29:0 2>/dev/null
    fi
    sleep 0.35
fi

uris="$(wl-paste -t text/uri-list 2>/dev/null || true)"
[ -n "$uris" ] || uris="$(wl-paste -n 2>/dev/null || true)"

# кліпборд як був
if [ "$saved" = 1 ]; then
    if [ -s "$tmp/clip" ]; then wl-copy <"$tmp/clip" 2>/dev/null; else wl-copy --clear 2>/dev/null; fi
fi

count="$(URI_LIST="$uris" CURSOR="$cursor" python3 - "$PAYLOAD" <<'PY'
import json, os, sys, urllib.parse

files = []
for line in os.environ.get("URI_LIST", "").splitlines():
    line = line.strip()
    if not line.startswith("file://"):
        continue
    path = urllib.parse.unquote(line[len("file://"):])
    if path.startswith("localhost/"):
        path = "/" + path[len("localhost/"):]
    if path not in files:
        files.append(path)

try:
    pos = json.loads(os.environ.get("CURSOR") or "{}")
except ValueError:
    pos = {}

with open(sys.argv[1], "w", encoding="utf-8") as f:
    json.dump({"files": files, "x": pos.get("x", 0), "y": pos.get("y", 0),
               "monitor": pos.get("monitor", "")}, f)
print(len(files))
PY
)"

if [ "${count:-0}" -eq 0 ]; then
    notify dialog-information "$(t 'Нічого конвертувати' 'Nothing to convert')" \
        "$(t 'Виділіть файли й натисніть Ctrl+C, потім Super + правий клік.' \
             'Select the files, press Ctrl+C, then Super + right click.')"
    exit 0
fi

# кільце в шелі (за потреби піднімаємо шел)
for attempt in 1 2 3; do
    if timeout 3 "$QS" -p "$SHELL_QML" ipc call convert open "$PAYLOAD" >/dev/null 2>&1; then
        exit 0
    fi
    if [ "$attempt" = 2 ]; then
        "$QS" -d -p "$SHELL_QML" >/dev/null 2>&1 &
    fi
    sleep 0.2
done

notify dialog-warning "$(t 'Шел не відповідає' 'The shell is not responding')" \
    "$(t 'Запустіть його: edots reload' 'Start it with: edots reload')"
exit 1
