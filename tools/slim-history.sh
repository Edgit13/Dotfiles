#!/usr/bin/env bash
#
# slim-history.sh — optional, destructive maintenance for the Edots repo.
#
# The current git pack is ~336 MB because old commits contain wallpaper images
# and compiled Rust artifacts. Removing the files from the working tree is not
# enough: they stay in history. This script rewrites history with git-filter-repo.
#
# This is NOT run by install.sh and is NOT run automatically. Read the warnings,
# make sure the repo is pushed somewhere first, then run it yourself.
#
# Usage:
#   ./tools/slim-history.sh            rewrite history (refuses on a dirty tree)
#   ./tools/slim-history.sh --force    rewrite even with local changes (dangerous)
#
set -euo pipefail

REPO_DIR="$(cd -- "$(dirname -- "$(readlink -f "$0")")/.." && pwd)"
cd "$REPO_DIR"

FORCE=0
[ "${1:-}" = "--force" ] && FORCE=1

if [ -n "$(git status --porcelain)" ] && [ "$FORCE" != 1 ]; then
    cat >&2 <<'EOF'
err  the working tree has uncommitted changes.

Commit or stash them first — rewriting history with local changes is how people
lose work. If you really know what you are doing: ./tools/slim-history.sh --force
EOF
    exit 1
fi

if ! command -v git-filter-repo >/dev/null 2>&1; then
    cat >&2 <<'EOF'
err  git-filter-repo is not installed.

  Arch:   sudo pacman -S git-filter-repo
  pipx:   pipx install git-filter-repo
  other:  https://github.com/newren/git-filter-repo
EOF
    exit 1
fi

BEFORE="$(du -sh .git | cut -f1)"
BUNDLE="$HOME/.local/share/edots-backups/edots-pre-slim-$(date +%Y%m%d-%H%M%S).bundle"
mkdir -p "$(dirname "$BUNDLE")"

echo "── safety bundle ──"
git bundle create "$BUNDLE" --all
echo "saved: $BUNDLE"
echo

echo "── rewriting history (this may take a minute) ──"
echo "before: $BEFORE"

# Only build output and the wallpaper dump are removed. Source files stay.
git filter-repo --force --invert-paths \
    --path wallpapers/ \
    --path edots/player/target/ \
    --path edots/edot-browser/build/ \
    --path edots/edot-brawser/build/ \
    --path edots/edot-browser/rust-adblock/target/

echo "after:  $(du -sh .git | cut -f1)"
echo
cat <<EOF
History rewritten.

git-filter-repo removes the 'origin' remote. To publish the slim history:
  git remote add origin https://github.com/Edgit13/Dotfiles.git
  git push --force-with-lease origin master

Restore the old repo from the bundle if needed:
  git clone $BUNDLE Dotfiles-restore
EOF
