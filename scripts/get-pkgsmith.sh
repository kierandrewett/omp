#!/usr/bin/env bash
# Build pkgsmith from source at the commit in scripts/pkgsmith-commit, and print the path of the binary.
# pkgsmith is not on crates.io yet, and its only tag (v0.1.0) is older than the script design this repo uses, so a
# commit on main is pinned instead. Raise it by changing scripts/pkgsmith-commit and running the packaging again.
# The formats are plugins that `cargo build --workspace` writes next to the binary, where pkgsmith finds them.
# Output: build/pkgsmith/target/release/pkgsmith. Needs git and a Rust toolchain.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

commit="$(tr -d '[:space:]' < "$root/scripts/pkgsmith-commit")"
[[ "$commit" =~ ^[0-9a-f]{40}$ ]] || die "scripts/pkgsmith-commit must hold a full commit hash"
src="$root/build/pkgsmith"
bin="$src/target/release/pkgsmith"

if [ ! -d "$src/.git" ]; then
    mkdir -p "$src"
    git -C "$src" init -q
    git -C "$src" remote add origin "${PKGSMITH_URL:-https://github.com/kierandrewett/pkgsmith.git}"
fi
if [ "$(git -C "$src" rev-parse HEAD 2>/dev/null || true)" != "$commit" ]; then
    log "fetching pkgsmith ${commit:0:10}"
    git -C "$src" fetch -q --depth 1 origin "$commit"
    git -C "$src" checkout -q --detach FETCH_HEAD
fi
[ "$(git -C "$src" rev-parse HEAD)" = "$commit" ] || die "pkgsmith checkout is not at $commit"

command -v cargo >/dev/null || die "cargo not found; install a Rust toolchain"
log "building pkgsmith ${commit:0:10}"
(cd "$src" && cargo build --release --workspace --locked) >&2
[ -x "$bin" ] || die "pkgsmith build produced no binary"

# The formats this repo writes must have loaded, or the packaging fails later with a less helpful message.
loaded="$("$bin" formats 2>/dev/null | awk '{print $1}')"
for format in rpm deb archlinux apk tar; do
    grep -qx "$format" <<<"$loaded" || die "pkgsmith loaded no '$format' plugin"
done
printf '%s\n' "$bin"
