#!/usr/bin/env bash
# Face ID launcher — picks the private OpenCV venv when it exists.
set -euo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
VENV="$HOME/.local/share/edots/faceid-venv"
PY="$VENV/bin/python"
action="${1:-status}"

# setup must work before the venv exists
if [ "$action" = "setup" ] || [ ! -x "$PY" ]; then
    exec python3 "$HERE/faceid.py" "$@"
fi

exec "$PY" "$HERE/faceid.py" "$@"
