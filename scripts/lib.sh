#!/usr/bin/env bash
# Shared helpers. Source this file; do not run it.
export PATH="$HOME/.local/bin:$HOME/.npm-global/bin:$PATH"

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
upstream="$root/upstream"
patch_dir="$root/patches"
series="$patch_dir/series"
work="$root/work/src"
build_tree="$root/build/src"
dist="$root/dist"

log() {
    printf '[omp] %s\n' "$*" >&2
}

die() {
    printf '[omp] error: %s\n' "$*" >&2
    exit 1
}

# The upstream commit the submodule pointer records (read from the index, so it works before the
# first commit). Patches are made against this commit.
pinned_commit() {
    git -C "$root" ls-files --stage upstream | awk 'NR == 1 { print $2 }'
}

# Print the patch names from the series file, one per line. Fails on a bad or missing entry.
series_patches() {
    [ -f "$series" ] || die "missing patch series: $series"
    local patch seen=" "
    while IFS= read -r patch || [ -n "$patch" ]; do
        [[ -z "$patch" || "$patch" == \#* ]] && continue
        [[ "$patch" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*\.patch$ ]] || die "invalid patch name: $patch"
        [[ "$seen" != *" $patch "* ]] || die "duplicate patch: $patch"
        [ -s "$patch_dir/$patch" ] || die "missing or empty patch: $patch"
        seen+="$patch "
        printf '%s\n' "$patch"
    done < "$series"
}
