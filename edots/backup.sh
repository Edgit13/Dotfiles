#!/usr/bin/env bash
#
# backup.sh — archive the live configuration, not the repository.
#
#   edots backup                 runtime config -> ~/Backups/edots-<stamp>.tar.gz
#   edots backup --full          also include terminals, fish, rofi, fastfetch
#   edots backup /some/dir       write the archive somewhere else
#
# The archive holds the JSON state the shell writes (bar, theme, notifications,
# night light, display state) plus the MangoWM config. Face ID embeddings are
# personal biometric data and are excluded unless --faceid is passed.
#
set -euo pipefail

CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}"
DEST="$HOME/Backups"
FULL=0
FACEID=0

for arg in "$@"; do
    case "$arg" in
        --full)   FULL=1 ;;
        --faceid) FACEID=1 ;;
        -h|--help)
            awk 'NR==1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "${BASH_SOURCE[0]}"
            exit 0
            ;;
        -*)
            printf 'err  unknown flag: %s\n' "$arg" >&2
            exit 1
            ;;
        *)
            DEST="$arg"
            ;;
    esac
done

[ -d "$CONFIG" ] || { printf 'err  no config directory at %s\n' "$CONFIG" >&2; exit 1; }

STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="$DEST/edots-$STAMP.tar.gz"
mkdir -p "$DEST"

targets=()
add() { if [ -e "$CONFIG/$1" ]; then targets+=("$1"); fi; }

# Shell state (small, and the part people actually lose)
for f in quickshell/*.json quickshell/active-preset quickshell/presets; do
    add "$f"
done
# Window manager + session
add mango
add systemd/user
# Terminals and launcher, only in --full
if [ "$FULL" = 1 ]; then
    for d in fish ghostty kitty rofi fastfetch alacritty; do
        add "$d"
    done
fi
# Biometrics are opt-in
[ "$FACEID" = 1 ] && add quickshell/faceid

if [ "${#targets[@]}" -eq 0 ]; then
    printf 'err  nothing to back up under %s\n' "$CONFIG" >&2
    exit 1
fi

printf '::  archiving %d paths from %s\n' "${#targets[@]}" "$CONFIG"
# --dereference: ~/.config/quickshell and ~/.config/mango are symlinks into the
# repository; without it the archive would contain two useless symlinks.
tar --create --gzip --dereference --file "$OUT" --directory "$CONFIG" "${targets[@]}"

SIZE="$(du -h "$OUT" | cut -f1)"
printf '\033[32mdone\033[0m  %s (%s)\n' "$OUT" "$SIZE"
printf 'restore with:  tar -xzf %q -C %q\n' "$OUT" "$CONFIG"
