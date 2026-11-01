#!/usr/bin/env bash
# Write the commits on top of the pinned upstream commit in work/src back to patches/.
# Each commit becomes one plain `git diff --binary` patch; the commit subject names the file.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

[ -d "$work" ] || die "no work tree; run scripts/work.sh first"
[ -z "$(git -C "$work" status --porcelain)" ] || die "work tree has uncommitted changes; commit or stash them"

pinned="$(pinned_commit)"
git -C "$work" merge-base --is-ancestor "$pinned" HEAD || die "work tree does not descend from $pinned"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
index=0
: > "$tmp/series"
while IFS= read -r commit; do
    index=$((index + 1))
    subject="$(git -C "$work" log -1 --format=%s "$commit")"
    slug="$(tr '[:upper:]' '[:lower:]' <<<"$subject" | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')"
    [ -n "$slug" ] || die "commit $commit has no usable subject"
    name="$(printf '%04d-%s.patch' "$index" "$slug")"
    git -C "$work" diff --binary "$commit^" "$commit" > "$tmp/$name"
    [ -s "$tmp/$name" ] || die "commit '$subject' is empty"
    printf '%s\n' "$name" >> "$tmp/series"
done < <(git -C "$work" rev-list --reverse --no-merges "$pinned..HEAD")
[ "$index" -gt 0 ] || die "no commits above $pinned; refusing to write an empty series"

mkdir -p "$patch_dir"
rm -f "$patch_dir"/*.patch
cp "$tmp"/*.patch "$patch_dir/"
cp "$tmp/series" "$series"
log "wrote $index patches"
cat "$series" >&2
