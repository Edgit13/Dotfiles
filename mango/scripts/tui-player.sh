#!/usr/bin/env bash
# Start the optional Edots TUI player only when it is actually installed.
# Used by mango/autostart.conf so a missing optional component never produces
# a failed autostart entry on login.
set -u

PLAYER="${EDOTS_TUI_PLAYER:-$HOME/edots/tui-player/forks/player.py}"

if [ -f "$PLAYER" ]; then
    exec python3 "$PLAYER" -d
fi

exit 0
