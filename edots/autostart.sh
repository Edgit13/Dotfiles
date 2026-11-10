#!/usr/bin/bash

# Start the optional TUI player daemon only if it has been built.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLAYER="$SCRIPT_DIR/player/target/release/player"

if [ -x "$PLAYER" ]; then
    "$PLAYER" --daemon &
fi
