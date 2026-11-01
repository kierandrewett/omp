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
# pkgsmith names an apk name-version-rRELEASE.apk, with no architecture, so the amd64 and arm64 apks would share one file
# name and one release could not hold both. `build` renames it to name-version-rRELEASE-<alpine arch>.apk, for example
# omp-18.14.2-r4-x86_64.apk. apk reads the name and version from inside the file, so the new name does not matter to it.
# `plan` still shows the name pkgsmith gives.
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

status=0
"$pkgsmith" "$command" "$root" "${args[@]}" "$@" || status=$?

if [ "$command" = build ] && [ "$status" -eq 0 ]; then
    case "$pkg_arch" in
        amd64) alpine_arch=x86_64 ;;
        arm64) alpine_arch=aarch64 ;;
        *) die "no Alpine name for architecture '$pkg_arch'" ;;
    esac
    for apk in "$out"/omp-*-r"$revision".apk; do
        [ -e "$apk" ] || continue
        mv -- "$apk" "${apk%.apk}-$alpine_arch.apk"
        log "apk renamed to $(basename "${apk%.apk}-$alpine_arch.apk")"
    done
fi
exit "$status"
