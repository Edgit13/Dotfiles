#!/usr/bin/env bash
# Lens capture — part of the bar shell's screentool (Region → Lens).
# Kept as a wrapper for the old SUPER+SHIFT+U bind.
set -u

if command -v edots >/dev/null 2>&1; then
    exec edots lens
fi

exec qs -p "${EDOTS_SHELL:-$HOME/.config/quickshell/bar/shell.qml}" ipc call screentool lens
