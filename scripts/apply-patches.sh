#!/usr/bin/env bash
# Apply the whole series to a clean upstream checkout, staged but not committed.
# Usage: apply-patches.sh <source-dir>
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

[ $# -eq 1 ] || die "usage: apply-patches.sh <source-dir>"
src="$1"
count=0
while IFS= read -r patch; do
    log "applying $patch"
    git -C "$src" apply --index --whitespace=nowarn "$patch_dir/$patch"
    count=$((count + 1))
done < <(series_patches)
[ "$count" -gt 0 ] || die "patch series is empty; refusing to build plain upstream"
log "applied $count patches"
