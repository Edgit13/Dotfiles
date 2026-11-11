#!/usr/bin/env bash
#
# tools/deploy-docs.sh — publish the static site to the docs server.
#
#   ./tools/deploy-docs.sh
#   EDOTS_DOCS_HOST=user@host EDOTS_DOCS_DIR=/srv/edots ./tools/deploy-docs.sh
#
# rsync only. No credentials are stored here: ssh either uses your key or asks
# for the password interactively. The service on the other side is a plain
# `python3 -m http.server` unit — see tools/systemd/edots-site.service.
#
set -euo pipefail

REPO_DIR="$(cd -- "$(dirname -- "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
HOST="${EDOTS_DOCS_HOST:-eduard@192.168.1.103}"
DIR="${EDOTS_DOCS_DIR:-/home/eduard/edots-site}"

info() { printf '\033[35m::\033[0m  %s\n' "$*"; }
die()  { printf '\033[31merr\033[0m  %s\n' "$*" >&2; exit 1; }

command -v rsync >/dev/null 2>&1 || die "rsync is not installed"
[ -d "$REPO_DIR/docs" ] || die "docs/ not found"

info "deploying docs/ to $HOST:$DIR"
rsync -az --delete --itemize-changes \
    -e "ssh -o ConnectTimeout=8" \
    "$REPO_DIR/docs/" "$HOST:$DIR/"

info "done — http://${HOST#*@}:8091/"
