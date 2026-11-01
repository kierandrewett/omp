#!/usr/bin/env bash
# Create work/src: a worktree at the pinned upstream commit with every patch applied as one commit.
# Edit and commit there, then run scripts/export.sh to write the patches back.
# Usage: work.sh [--reset]
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

reset=false
[ "${1:-}" = "--reset" ] && reset=true

pinned="$(pinned_commit)"
git -C "$upstream" cat-file -e "$pinned^{commit}" 2>/dev/null || die "upstream does not have $pinned; run: git submodule update --init"

if [ -e "$work" ]; then
    $reset || die "$work exists; use --reset to throw it away (unexported commits are lost)"
    git -C "$upstream" worktree remove --force "$work"
fi
mkdir -p "$(dirname "$work")"
git -C "$upstream" worktree add --detach "$work" "$pinned" >/dev/null
log "work tree at $(git -C "$work" describe --tags --always)"

while IFS= read -r patch; do
    log "applying $patch"
    if ! git -C "$work" apply --3way --index --whitespace=nowarn "$patch_dir/$patch"; then
        log "conflict in $patch"
        log "resolve in $work, run 'git add' on each file, then 'git commit -m \"<name>\"'"
        log "then apply the later patches by hand, or run: just export"
        exit 1
    fi
    # The subject is the patch name without its number prefix and extension.
    subject="$(sed -E 's/^[0-9]+-//; s/\.patch$//; s/-/ /g' <<<"$patch")"
    git -C "$work" commit -q -m "$subject"
done < <(series_patches)
log "ready: $work"
