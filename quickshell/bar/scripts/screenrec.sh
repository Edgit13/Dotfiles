#!/usr/bin/env bash
# screenrec.sh — запис екрана через wf-recorder. Живе незалежно від shell.
#
#   screenrec.sh start [--audio system|mic|none] [--fps N] [--encoder software|vaapi]
#                      [--geometry "x,y WxH" | --output NAME] [--delay SEC]
#   screenrec.sh stop
#   screenrec.sh status        (прибирає застарілий стан)
#
# Конфіг пише RecordService (~/.cache/quickshell/screenrec.conf), стан читає він же
# (~/.cache/quickshell/screenrec.state: pid= / start= / file=).

CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/quickshell"
CONF="$CACHE/screenrec.conf"
STATE="$CACHE/screenrec.state"
mkdir -p "$CACHE"

# значення за замовчуванням (перекриваються конфігом)
AUDIO=system FPS=30 ENCODER=software DIR='~/Videos/Recordings' NOTIFY=1
MSG_DONE='Recording saved' MSG_FAIL='Recording failed' MSG_SOON='Recording starts in %s s'
MSG_MISSING='wf-recorder is not installed'
LBL_OPEN='Open' LBL_FOLDER='Show in folder' LBL_COPY='Copy path'
# shellcheck disable=SC1090
[ -f "$CONF" ] && . "$CONF"

notify() { command -v notify-send >/dev/null 2>&1 && notify-send -a "Screen recording" "$@"; }

state_get() { sed -n "s/^$1=//p" "$STATE" 2>/dev/null | head -n1; }

is_running() {
    local pid
    pid=$(state_get pid)
    [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null && grep -q wf-recorder "/proc/$pid/comm" 2>/dev/null
}

cleanup_stale() { is_running || rm -f "$STATE"; }

expand_dir() {
    case "$1" in
        "~")   printf '%s' "$HOME" ;;
        "~/"*) printf '%s' "$HOME/${1#\~/}" ;;
        *)     printf '%s' "$1" ;;
    esac
}

# ───────────────────────── внутрішній запуск (в окремій сесії) ─────────────────────────
if [ "$1" = "_run" ]; then
    shift
    file="$1"; shift
    wf-recorder "$@" -f "$file" &
    pid=$!
    printf 'pid=%s\nstart=%s\nfile=%s\n' "$pid" "$(date +%s)" "$file" > "$STATE"
    wait "$pid"
    rc=$?
    rm -f "$STATE"
    # SIGINT (штатна зупинка) дає 0 або 130 — обидва вважаємо успіхом, якщо файл існує
    if [ -s "$file" ] && { [ "$rc" -eq 0 ] || [ "$rc" -eq 130 ] || [ "$rc" -eq 2 ]; }; then
        [ "$NOTIFY" = 1 ] || exit 0
        if notify-send --help 2>&1 | grep -q -- '--action'; then
            act=$(timeout 60 notify-send -a "Screen recording" -i video-x-generic \
                -A "open=$LBL_OPEN" -A "folder=$LBL_FOLDER" -A "copy=$LBL_COPY" \
                "$MSG_DONE" "$file" 2>/dev/null)
            case "$act" in
                open)   xdg-open "$file" >/dev/null 2>&1 ;;
                folder) xdg-open "$(dirname "$file")" >/dev/null 2>&1 ;;
                copy)   printf '%s' "$file" | wl-copy ;;
            esac
        else
            notify -i video-x-generic "$MSG_DONE" "$file"
        fi
    else
        rm -f "$file"
        notify -u critical "$MSG_FAIL"
    fi
    exit 0
fi

cmd="${1:-status}"; shift 2>/dev/null

case "$cmd" in
status)
    cleanup_stale
    is_running && echo recording || echo idle
    ;;

stop)
    if is_running; then
        pid=$(state_get pid)
        kill -INT "$pid"
        # wf-recorder завершує файл по SIGINT; якщо не відреагував — м'яко добиваємо SIGTERM
        for _ in 1 2 3 4 5 6; do
            kill -0 "$pid" 2>/dev/null || exit 0
            sleep 0.5
        done
        kill -TERM "$pid" 2>/dev/null
    else
        rm -f "$STATE"
    fi
    ;;

start)
    geometry="" output="" delay=0
    while [ $# -gt 0 ]; do
        case "$1" in
            --audio)    AUDIO="$2";    shift 2 ;;
            --fps)      FPS="$2";      shift 2 ;;
            --encoder)  ENCODER="$2";  shift 2 ;;
            --geometry) geometry="$2"; shift 2 ;;
            --output)   output="$2";   shift 2 ;;
            --delay)    delay="$2";    shift 2 ;;
            *) shift ;;
        esac
    done

    cleanup_stale
    # вже йде запис — повторний старт ігноруємо
    is_running && exit 0

    if ! command -v wf-recorder >/dev/null 2>&1; then
        notify -u critical "$MSG_MISSING"
        exit 1
    fi

    if [ "${delay:-0}" -gt 0 ] 2>/dev/null; then
        # shellcheck disable=SC2059
        notify -t 1500 "$(printf "$MSG_SOON" "$delay")"
    fi
    # дати оверлею вибору області зникнути + відлік
    sleep "$(awk -v d="${delay:-0}" 'BEGIN { printf "%.2f", 0.35 + d }')"

    dir=$(expand_dir "$DIR")
    mkdir -p "$dir" || { notify -u critical "$MSG_FAIL"; exit 1; }
    file="$dir/Recording_$(date +%Y-%m-%d_%H-%M-%S).mp4"

    args=(-r "$FPS")
    [ -n "$geometry" ] && args+=(-g "$geometry")
    [ -z "$geometry" ] && [ -n "$output" ] && args+=(-o "$output")

    case "$ENCODER" in
        vaapi)
            dev=$(ls /dev/dri/renderD* 2>/dev/null | head -n1)
            args+=(-c h264_vaapi -d "${dev:-/dev/dri/renderD128}")
            ;;
        *) args+=(-c libx264 -p preset=veryfast) ;;
    esac

    case "$AUDIO" in
        system)
            if command -v pactl >/dev/null 2>&1; then
                sink=$(pactl get-default-sink 2>/dev/null)
                [ -n "$sink" ] && args+=("--audio=${sink}.monitor")
            fi
            ;;
        mic)
            if command -v pactl >/dev/null 2>&1; then
                src=$(pactl get-default-source 2>/dev/null)
                [ -n "$src" ] && args+=("--audio=$src")
            fi
            ;;
    esac

    # окрема сесія — запис переживає перезапуск shell
    setsid -f "$0" _run "$file" "${args[@]}" >/dev/null 2>&1 </dev/null
    ;;

*)
    echo "usage: $0 start|stop|status" >&2
    exit 2
    ;;
esac
