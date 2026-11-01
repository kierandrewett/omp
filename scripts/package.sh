#!/usr/bin/env bash
# Run pkgsmith on the prefix with this repo's pkgsmith.star. Local runs and CI call this script.
#
# Usage: package.sh [plan | files | build] [pkgsmith options]     default command: build
#   package.sh plan                  which packages, which file names
#   package.sh files -F deb          what the deb would carry
#   package.sh build -F rpm,deb      write only these formats
#
# Environment:
#   PREFIX    the prefix to pack                  default: build/prefix (see scripts/install-prefix.sh)
#   OUTPUT    where `build` writes the packages   default: dist/packages
#   PKGSMITH  a pkgsmith binary                   default: scripts/get-pkgsmith.sh builds the pinned one
# The architecture and the C library are read from the ELF headers of usr/bin/omp in the prefix, not from this machine
# and not from a flag. A glibc binary therefore never gets an apk: Alpine has musl and the binary would not run there.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

command="${1:-build}"
[ $# -eq 0 ] || shift
case "$command" in
    plan | files | build) ;;
    *) die "unknown command '$command'; use plan, files or build" ;;
esac

prefix="${PREFIX:-$root/build/prefix}"
[ -d "$prefix" ] || die "no prefix at $prefix; run scripts/install-prefix.sh first"

binary="$prefix/usr/bin/omp"
[ -f "$binary" ] || die "no $binary in the prefix"
pkg_arch="$(elf_arch "$binary")"
libc="$(elf_libc "$binary")"
log "prefix binary: $pkg_arch, $libc"
eval "$("$root/scripts/release-info.sh")"

pkgsmith="${PKGSMITH:-$("$root/scripts/get-pkgsmith.sh")}"
[ -x "$pkgsmith" ] || die "pkgsmith not found at $pkgsmith"

# The same prefix, script and time stamp give the same package. Use the time of the commit being packaged.
export SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-$(git -C "$root" log -1 --format=%ct)}"

args=(--prefix "$prefix"
    --build-arg "VERSION=$version" --build-arg "RELEASE=$revision" --build-arg "ARCH=$pkg_arch"
    --build-arg "LIBC=$libc")
if [ "$command" = build ]; then
    out="${OUTPUT:-$dist/packages}"
    mkdir -p "$out"
    args+=(--output "$out")
fi

exec "$pkgsmith" "$command" "$root" "${args[@]}" "$@"
