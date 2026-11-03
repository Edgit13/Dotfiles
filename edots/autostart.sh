#!/usr/bin/bash

# Start the optional TUI player only if it is installed.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLAYER="$SCRIPT_DIR/tui-player/forks/player.py"

if [ -f "$PLAYER" ]; then
    python3 "$PLAYER" -d &
fi
