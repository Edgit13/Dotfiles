#!/usr/bin/env bash
#
# tools/release.sh — cut a versioned release.
#
#   ./tools/release.sh 1.2.0
#
# Steps: refuse a dirty tree, require a CHANGELOG section for the version,
# run the linter, then create an annotated tag. Nothing is pushed; the command
# to push is printed at the end.
#
set -euo pipefail

REPO_DIR="$(cd -- "$(dirname -- "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
cd "$REPO_DIR"

die() { printf '\033[31merr\033[0m  %s\n' "$*" >&2; exit 1; }
info() { printf '\033[35m::\033[0m  %s\n' "$*"; }

VERSION="${1:-}"
[ -n "$VERSION" ] || die "usage: tools/release.sh <version>   e.g. 1.2.0"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "version must be X.Y.Z"
TAG="v$VERSION"

if [ -n "$(git status --porcelain)" ]; then
    die "the working tree is dirty — commit or stash first"
fi

git rev-parse -q --verify "refs/tags/$TAG" >/dev/null && die "tag $TAG already exists"
grep -qE "^## \[$VERSION\]" CHANGELOG.md || \
    die "CHANGELOG.md has no '## [$VERSION]' section — write the notes first"

if [ -x tools/lint.sh ]; then
    info "linting"
    ./tools/lint.sh || die "lint failed — fix the errors before tagging"
fi

info "tagging $TAG"
git tag -a "$TAG" -m "Edots $VERSION"

printf '\n\033[32mdone\033[0m  created %s\n' "$TAG"
printf 'push it with:\n\n  git push origin %s --follow-tags\n\n' "$(git branch --show-current)"
