#!/usr/bin/env bash
# Install the built omp binary into a prefix: a folder laid out like an installed system. pkgsmith packs that folder.
# pkgsmith builds nothing, so this is the step that decides what a package holds. Local runs and CI both call it.
#
#   prefix/usr/bin/omp
#   prefix/usr/share/licenses/omp/NOTICE.md
#
# Usage: install-prefix.sh [PREFIX]    default: build/prefix
# Reads dist/omp-linux-<arch>, and runs scripts/build.sh first when that file is missing.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

prefix="${1:-$root/build/prefix}"
case "$prefix" in
    "" | / | "$HOME" | "$root") die "refusing to use '$prefix' as a prefix; it is emptied first" ;;
esac

arch="$(target_arch)"
bin="$dist/omp-linux-$arch"
if [ ! -s "$bin" ]; then
    log "no $bin; building it"
    "$root/scripts/build.sh"
fi
[ -s "$bin" ] || die "no binary at $bin"

# A binary for this machine must run and report the release it was built for. Another arch cannot run here.
if [ "$arch" = "$(TARGET_ARCH='' target_arch)" ]; then
    eval "$("$root/scripts/release-info.sh")"
    [ "$("$bin" --version)" = "omp/${fork_tag#v}" ] || die "$bin reports '$("$bin" --version)', expected omp/${fork_tag#v}"
fi

rm -rf "$prefix"
install -Dm755 "$bin" "$prefix/usr/bin/omp"
install -Dm644 "$root/NOTICE.md" "$prefix/usr/share/licenses/omp/NOTICE.md"

log "prefix ready at $prefix"
(cd "$prefix" && find . -type f -printf '%m %s %p\n' | sort -k3) >&2
