#!/usr/bin/env bash
# Move the upstream submodule to a release tag (default: the newest stable vX.Y.Z tag).
# Then rebuild work/src so conflicts show up straight away.
# Usage: update-upstream.sh [tag]
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

git -C "$upstream" fetch --tags origin
tag="${1:-}"
if [ -z "$tag" ]; then
    tag="$(git -C "$upstream" tag -l 'v[0-9]*.[0-9]*.[0-9]*' | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -n 1)"
fi
[ -n "$tag" ] || die "no stable upstream tag found"

if [ -e "$work" ]; then
    git -C "$upstream" worktree remove --force "$work"
fi
git -C "$upstream" checkout -q "$tag"
log "upstream is now $tag ($(git -C "$upstream" rev-parse --short HEAD))"
log "commit the new submodule pointer once the patches apply: git add upstream"
exec "$(dirname "${BASH_SOURCE[0]}")/work.sh"
