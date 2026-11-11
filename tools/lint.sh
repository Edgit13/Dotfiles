#!/usr/bin/env bash
#
# tools/lint.sh — static checks for the whole repository.
#
#   ./tools/lint.sh            check everything (default)
#   ./tools/lint.sh --qml      QML/JS syntax only (fast)
#
# What runs:
#   • QML/JS  — qmllint in syntax-only mode (no Quickshell types needed)
#   • shell   — shellcheck at error level, when installed
#   • python  — ast.parse, so no __pycache__ is written
#   • json    — every tracked *.json must parse
#
# Exit code is non-zero if anything fails. Missing optional tools are reported
# as warnings, not failures, so the script is usable on a minimal machine.
#
set -uo pipefail

REPO_DIR="$(cd -- "$(dirname -- "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
cd "$REPO_DIR" || exit 1

QML_ONLY=0
[ "${1:-}" = "--qml" ] && QML_ONLY=1

fail=0
count=0

section() { printf '\n\033[1m%s\033[0m\n' "$*"; }
ok()      { printf '  \033[32mok\033[0m    %s\n' "$*"; }
warn()    { printf '  \033[33mwarn\033[0m  %s\n' "$*"; }
err()     { printf '  \033[31mfail\033[0m  %s\n' "$*"; fail=1; }

files() {
    # Tracked files plus untracked-but-not-ignored, so a new file is checked
    # before it is staged. --exclude-standard honours .gitignore.
    git ls-files --cached --others --exclude-standard -- "$@" 2>/dev/null
}

section "QML / JS syntax"
# Qt 5's qmllint cannot cope with this tree: it stops at Qt 6 syntax
# (inline components, `root:` imports) and reports every file as broken.
# Require Qt 6 and run it with --bare, which parses without resolving imports,
# so no Quickshell installation is needed.
find_qmllint() {
    local candidate
    for candidate in /usr/lib/qt6/bin/qmllint qmllint6 qmllint; do
        command -v "$candidate" >/dev/null 2>&1 || continue
        "$candidate" --version 2>/dev/null | grep -qE '^qmllint 6' && { printf '%s' "$candidate"; return 0; }
    done
    return 1
}

if ! QMLLINT="$(find_qmllint)"; then
    warn "Qt 6 qmllint not found — skipping QML (install qt6-declarative)"
else
    mapfile -t qml < <(files '*.qml' '*.js' | grep -v '^docs/')
    if [ "${#qml[@]}" -eq 0 ]; then
        warn "no QML/JS files found"
    else
        # --bare still prints import warnings; only the exit code tells us
        # whether parsing failed, so the output is filtered on failure.
        if out="$("$QMLLINT" --bare "${qml[@]}" 2>&1)"; then
            ok "${#qml[@]} QML/JS files"
        else
            printf '%s\n' "$out" \
                | grep -E -A1 '\[syntax\]|\[compiler\]' \
                | sed 's/^/        /' | head -60
            err "${#qml[@]} QML/JS files contain syntax errors"
        fi
        count=$((count + ${#qml[@]}))
    fi
fi

[ "$QML_ONLY" = 1 ] && { printf '\n'; exit "$fail"; }

section "Shell scripts"
if ! command -v shellcheck >/dev/null 2>&1; then
    warn "shellcheck is not installed — skipping shell scripts"
else
    mapfile -t sh < <(files '*.sh')
    # Error level only: the repo predates shellcheck and style warnings are
    # not worth breaking a commit over. Real bugs (bad expansion, syntax) are.
    if [ "${#sh[@]}" -gt 0 ] && out="$(shellcheck -S error -x "${sh[@]}" 2>&1)"; then
        ok "${#sh[@]} shell scripts"
        count=$((count + ${#sh[@]}))
    else
        printf '%s\n' "$out" | sed 's/^/        /' | head -60
        err "shellcheck reported errors"
    fi
fi

section "Python"
if ! command -v python3 >/dev/null 2>&1; then
    warn "python3 is not installed — skipping Python"
else
    mapfile -t py < <(files '*.py')
    if [ "${#py[@]}" -eq 0 ]; then
        warn "no Python files found"
    elif python3 - "${py[@]}" <<'PY'
import ast
import sys

bad = 0
for path in sys.argv[1:]:
    try:
        with open(path, "rb") as fh:
            ast.parse(fh.read(), path)
    except SyntaxError as exc:
        bad = 1
        print(f"{path}:{exc.lineno}: {exc.msg}")
    except OSError as exc:
        bad = 1
        print(f"{path}: {exc}")
sys.exit(bad)
PY
    then
        ok "${#py[@]} Python files"
        count=$((count + ${#py[@]}))
    else
        err "Python syntax errors"
    fi
fi

section "JSON"
if ! command -v python3 >/dev/null 2>&1; then
    warn "python3 is not installed — skipping JSON"
else
    mapfile -t json < <(files '*.json')
    if [ "${#json[@]}" -eq 0 ]; then
        warn "no JSON files found"
    elif python3 - "${json[@]}" <<'PY'
import json
import sys

bad = 0
for path in sys.argv[1:]:
    try:
        with open(path, "rb") as fh:
            json.load(fh)
    except json.JSONDecodeError as exc:
        bad = 1
        print(f"{path}:{exc.lineno}:{exc.colno}: {exc.msg}")
    except OSError as exc:
        bad = 1
        print(f"{path}: {exc}")
sys.exit(bad)
PY
    then
        ok "${#json[@]} JSON files"
        count=$((count + ${#json[@]}))
    else
        err "JSON files do not parse"
    fi
fi

printf '\n'
if [ "$fail" -eq 0 ]; then
    printf '\033[32mAll checks passed\033[0m (%d files)\n' "$count"
else
    printf '\033[31mChecks failed\033[0m\n'
fi
exit "$fail"
