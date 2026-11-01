#!/usr/bin/env bash
# Install the built omp binary into a prefix: a folder laid out like an installed system. pkgsmith packs that folder.
# pkgsmith builds nothing, so this is the step that decides what a package holds. Local runs and CI both call it.
#
#   prefix/usr/bin/omp
#   prefix/usr/share/licenses/omp/NOTICE.md
#
# Usage: install-prefix.sh [PREFIX]    default: build/prefix
# Reads dist/omp-linux-<arch>, or dist/omp-linux-musl-<arch> with LIBC=musl, and runs scripts/build.sh first when that
# file is missing. Both land in the same prefix path, usr/bin/omp: the packages of one build hold one binary.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

prefix="${1:-$root/build/prefix}"
case "$prefix" in
    "" | / | "$HOME" | "$root") die "refusing to use '$prefix' as a prefix; it is emptied first" ;;
esac

arch="$(target_arch)"
libc="$(target_libc)"
bin="$dist/$(binary_name "$arch" "$libc")"
if [ ! -s "$bin" ]; then
    log "no $bin; building it"
    "$root/scripts/build.sh"
fi
[ -s "$bin" ] || die "no binary at $bin"

# A binary this machine can run must report the release it was built for. Another architecture, or musl on a glibc
# machine, cannot run here; scripts/smoke-packages.sh runs it in a container of its own distro.
if runs_here "$arch" "$libc"; then
    eval "$("$root/scripts/release-info.sh")"
    [ "$("$bin" --version)" = "omp/${fork_tag#v}" ] || die "$bin reports '$("$bin" --version)', expected omp/${fork_tag#v}"
fi

rm -rf "$prefix"
install -Dm755 "$bin" "$prefix/usr/bin/omp"
install -Dm644 "$root/NOTICE.md" "$prefix/usr/share/licenses/omp/NOTICE.md"

log "prefix ready at $prefix"
(cd "$prefix" && find . -type f -printf '%m %s %p\n' | sort -k3) >&2
