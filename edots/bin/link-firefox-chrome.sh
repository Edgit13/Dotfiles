#!/usr/bin/env bash
#
# link-firefox-chrome.sh — link the Edots Firefox chrome files into every
# installed Firefox profile, and enable the legacy stylesheet pref.
#
# Usage:
#   ./link-firefox-chrome.sh                 link every detected profile
#   ./link-firefox-chrome.sh --check         report status, change nothing
#   ./link-firefox-chrome.sh --dry-run       show what would happen
#   ./link-firefox-chrome.sh /path/profile   link one explicit profile
#
set -uo pipefail

SELF="$(readlink -f "${BASH_SOURCE[0]}")"
REPO_DIR="$(cd -- "$(dirname -- "$SELF")/../.." && pwd)"
SRC_CHROME="$REPO_DIR/firefox/chrome/userChrome.css"
SRC_CONTENT="$REPO_DIR/firefox/chrome/userContent.css"
STAMP="$(date +%Y%m%d-%H%M%S)"
PREF='user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);'

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    C_OK=$'\033[0;32m'; C_WARN=$'\033[0;33m'; C_ERR=$'\033[0;31m'
    C_DIM=$'\033[2m'; C_OFF=$'\033[0m'
else
    C_OK=''; C_WARN=''; C_ERR=''; C_DIM=''; C_OFF=''
fi

CHECK=0
DRY=0
PROFILES=()

for arg in "$@"; do
    case "$arg" in
        --check)   CHECK=1 ;;
        --dry-run) DRY=1 ;;
        -h|--help)
            sed -n '2,12p' "$SELF" | sed 's/^# \{0,1\}//'
            exit 0 ;;
        -*)
            printf '%serr%s  unknown option: %s\n' "$C_ERR" "$C_OFF" "$arg" >&2
            exit 1 ;;
        *) PROFILES+=("$arg") ;;
    esac
done

[ -f "$SRC_CHROME" ]  || { printf '%serr%s  missing: %s\n' "$C_ERR" "$C_OFF" "$SRC_CHROME" >&2; exit 1; }
[ -f "$SRC_CONTENT" ] || { printf '%serr%s  missing: %s\n' "$C_ERR" "$C_OFF" "$SRC_CONTENT" >&2; exit 1; }

detect_profiles() {
    python3 - <<'PY'
import configparser, os
from pathlib import Path

home = Path.home()
xdg = Path(os.environ.get("XDG_CONFIG_HOME", home / ".config"))
roots = [xdg / "mozilla" / "firefox", home / ".mozilla" / "firefox"]

inifiles = []
for root in roots:
    ini = root / "profiles.ini"
    if ini.is_file():
        inifiles.append(ini)

installed, defaults = [], []
for ini in inifiles:
    cp = configparser.RawConfigParser(strict=False)
    try:
        cp.read(ini, encoding="utf-8")
    except Exception:
        continue

    # Install sections point at the profile Firefox actually launches.
    for sec in cp.sections():
        if not sec.startswith("Install") or not cp.has_option(sec, "Default"):
            continue
        raw = cp.get(sec, "Default").strip()
        cand = Path(raw)
        if not cand.is_absolute():
            cand = ini.parent / cand
        if cand.is_dir():
            installed.append(cand)

    # Fallback: the profile marked Default=1.
    for sec in cp.sections():
        if not sec.startswith("Profile"):
            continue
        if cp.get(sec, "Default", fallback="").strip() != "1":
            continue
        raw = cp.get(sec, "Path", fallback="").strip()
        if not raw:
            continue
        relative = cp.get(sec, "IsRelative", fallback="1").strip() not in ("0", "false", "False")
        cand = (ini.parent / raw) if relative else Path(raw)
        if cand.is_dir():
            defaults.append(cand)

# Prefer the profiles Firefox is actually configured to launch; only fall back
# to Default=1 or to scanning when no Install section exists.
found = installed or defaults
if not found:
    for root in roots:
        if root.is_dir():
            for cand in root.glob("*.default*"):
                if cand.is_dir() and (cand / "prefs.js").is_file():
                    found.append(cand)

seen, out = set(), []
for p in found:
    try:
        resolved = str(p.resolve())
    except OSError:
        continue
    if resolved not in seen:
        seen.add(resolved)
        out.append(resolved)

print("\n".join(out))
PY
}

if [ "${#PROFILES[@]}" -eq 0 ]; then
    mapfile -t PROFILES < <(detect_profiles)
fi

if [ "${#PROFILES[@]}" -eq 0 ]; then
    [ "$CHECK" = 1 ] && exit 2
    printf '%s!%s  no Firefox profile found (is Firefox installed?)\n' "$C_WARN" "$C_OFF" >&2
    exit 2
fi

link_one() {
    local src="$1" dst="$2"

    if [ -L "$dst" ] && [ "$(readlink -f "$dst")" = "$(readlink -f "$src")" ]; then
        printf '  %s✓%s %s\n' "$C_OK" "$C_OFF" "$dst"
        return 0
    fi

    if [ "$DRY" = 1 ]; then
        printf '  %sDRY%s link %s -> %s\n' "$C_DIM" "$C_OFF" "$dst" "$src"
        return 0
    fi

    if [ -e "$dst" ] && [ ! -L "$dst" ]; then
        local backup="$dst.edots-backup-$STAMP"
        cp -a "$dst" "$backup" \
            && printf '  %s!%s backup %s\n' "$C_WARN" "$C_OFF" "$backup" \
            || { printf '  %s✗%s could not back up %s\n' "$C_ERR" "$C_OFF" "$dst"; return 1; }
    fi

    ln -sfn "$src" "$dst" \
        && printf '  %s✓%s %s -> %s\n' "$C_OK" "$C_OFF" "$dst" "$src" \
        || { printf '  %s✗%s failed to link %s\n' "$C_ERR" "$C_OFF" "$dst"; return 1; }
}

check_one() {
    local profile="$1" ok=1
    if [ -L "$profile/chrome/userChrome.css" ] && [ -L "$profile/chrome/userContent.css" ]; then
        if [ -f "$profile/user.js" ] && grep -qF 'toolkit.legacyUserProfileCustomizations.stylesheets' "$profile/user.js"; then
            printf '  %s✓%s %s\n' "$C_OK" "$C_OFF" "$profile"
        else
            printf '  %s!%s %s (links ok, user.js pref missing)\n' "$C_WARN" "$C_OFF" "$profile"
            ok=0
        fi
    else
        printf '  %s✗%s %s (chrome files not linked)\n' "$C_ERR" "$C_OFF" "$profile"
        ok=0
    fi
    return $((1 - ok))
}

status=0
for profile in "${PROFILES[@]}"; do
    if [ "$CHECK" = 1 ]; then
        check_one "$profile" || status=1
        continue
    fi

    printf '%sProfile:%s %s\n' "$C_DIM" "$C_OFF" "$profile"
    if [ "$DRY" != 1 ]; then
        mkdir -p "$profile/chrome" || { status=1; continue; }
    fi

    link_one "$SRC_CHROME"  "$profile/chrome/userChrome.css"  || status=1
    link_one "$SRC_CONTENT" "$profile/chrome/userContent.css" || status=1

    userjs="$profile/user.js"
    if [ -f "$userjs" ] && grep -qF 'toolkit.legacyUserProfileCustomizations.stylesheets' "$userjs"; then
        printf '  %s✓%s user.js already enables the chrome stylesheet\n' "$C_OK" "$C_OFF"
    elif [ "$DRY" = 1 ]; then
        printf '  %sDRY%s append stylesheet pref to %s\n' "$C_DIM" "$C_OFF" "$userjs"
    else
        if [ -f "$userjs" ]; then
            cp -a "$userjs" "$userjs.edots-backup-$STAMP"
        fi
        {
            [ -s "$userjs" ] && printf '\n'
            printf '// Edots: load userChrome.css / userContent.css\n%s\n' "$PREF"
        } >> "$userjs" \
            && printf '  %s✓%s enabled stylesheet pref in user.js\n' "$C_OK" "$C_OFF" \
            || { printf '  %s✗%s could not write %s\n' "$C_ERR" "$C_OFF" "$userjs"; status=1; }
    fi
done

if [ "$CHECK" = 0 ] && [ "$DRY" = 0 ] && [ "$status" = 0 ]; then
    printf '\nRestart Firefox to apply the Edots chrome.\n'
fi

exit "$status"
