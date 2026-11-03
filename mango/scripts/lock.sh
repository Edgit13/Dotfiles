#!/usr/bin/env bash
# Legacy swaylock fallback (the active lock screen is the Quickshell one).
# Ask awww what is actually displayed; fall back to the saved path.
WP="$(awww query 2>/dev/null | sed -nE 's/.*currently displaying: (image|animated|video): //p' | head -n1 || true)"
if [ -z "${WP:-}" ]; then
    WP="$(head -n1 "$HOME/.config/quickshell/current-wallpaper.txt" 2>/dev/null || true)"
fi
exec swaylock -i "${WP:-}"
