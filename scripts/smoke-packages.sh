#!/usr/bin/env bash
# Install every package in a folder in a throwaway container of its own distro, then check that the package manager
# owns /usr/bin/omp and that the installed program reports this release and passes its own smoke test.
# Local runs and CI both call this. Containers are removed afterwards; nothing is installed on this machine.
#
# Usage: smoke-packages.sh [DIR]     default: dist/packages
# Environment: ENGINE   podman or docker (default: podman if present, else docker)
#              ONLY     comma separated formats to check, for example rpm,deb
#              STATIC_ARCHLINUX=1   check the Arch package by its contents instead of installing it
# The images are the ones of each distro for the architecture of this machine, so an arm64 runner checks arm64.
# Arch Linux has no official arm64 image (Arch Linux ARM is a separate project), so on arm64 the Arch package is
# checked by its contents only: the file list and the architecture in .PKGINFO. It is not installed there.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

dir="${1:-$dist/packages}"
[ -d "$dir" ] || die "no package folder at $dir"
dir="$(cd "$dir" && pwd)"
engine="${ENGINE:-$(command -v podman || command -v docker || true)}"
[ -n "$engine" ] || die "need podman or docker"
eval "$("$root/scripts/release-info.sh")"
expected="omp/${fork_tag#v}"

# What the program must pass once installed. HOME is empty so nothing of this machine's omp settings is read.
check='export HOME="$(mktemp -d)" XDG_DATA_HOME="$(mktemp -d)"
# Arch links /usr/sbin to /usr/bin, so compare the resolved path.
test "$(readlink -f "$(command -v omp)")" = /usr/bin/omp
test "$(omp --version)" = "'"$expected"'"
omp --smoke-test'

failed=0
checked=0

# run FORMAT IMAGE FILE-GLOB SCRIPT: install and check one package.
run() {
    local format="$1" image="$2" glob="$3" script="$4" file
    if [ -n "${ONLY:-}" ] && [[ ",$ONLY," != *",$format,"* ]]; then return 0; fi
    file="$(compgen -G "$dir/$glob" | head -n 1 || true)"
    if [ -z "$file" ]; then
        log "skip $format: no $glob in $dir"
        return 0
    fi
    checked=$((checked + 1))
    log "$format: $(basename "$file") in $image"
    if "$engine" run --rm --security-opt label=disable -v "$dir:/pkg:ro" "$image" sh -ec "$script
$check" >&2; then
        log "$format: ok"
    else
        log "$format: FAILED"
        failed=$((failed + 1))
    fi
}

# static_archlinux FILE: no container; check that the package holds usr/bin/omp and names this machine's architecture.
static_archlinux() {
    local file="$1" machine listing pkginfo
    machine="$(uname -m)"
    checked=$((checked + 1))
    log "archlinux: $(basename "$file") by contents only (no official Arch Linux image for $machine)"
    # Capture first: `grep -q` stops at the first match, tar then dies of SIGPIPE, and pipefail calls that a failure.
    listing="$(tar --zstd -tf "$file")"
    pkginfo="$(tar --zstd -xOf "$file" .PKGINFO)"
    if grep -qx 'usr/bin/omp' <<<"$listing" && grep -qx "arch = $machine" <<<"$pkginfo"; then
        log "archlinux: contents ok, NOT installed"
    else
        log "archlinux: FAILED"
        failed=$((failed + 1))
    fi
}

run rpm fedora:latest 'omp-*.rpm' \
    'dnf install -y /pkg/omp-*.rpm >/dev/null
test "$(rpm -qf /usr/bin/omp)" = "$(rpm -qp --qf "%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}" /pkg/omp-*.rpm)"'
run deb debian:12 'omp_*.deb' \
    'apt-get install -y /pkg/omp_*.deb >/dev/null
dpkg -S /usr/bin/omp | grep -q "^omp: "'
if [ -n "${ONLY:-}" ] && [[ ",$ONLY," != *",archlinux,"* ]]; then
    :
elif [ -n "${STATIC_ARCHLINUX:-}" ] || [ "$(uname -m)" != x86_64 ]; then
    arch_file="$(compgen -G "$dir/omp-*.pkg.tar.zst" | head -n 1 || true)"
    if [ -n "$arch_file" ]; then static_archlinux "$arch_file"; else log "skip archlinux: no Arch package in $dir"; fi
else
    run archlinux archlinux:latest 'omp-*.pkg.tar.zst' \
        'pacman -U --noconfirm /pkg/omp-*.pkg.tar.zst >/dev/null
pacman -Qo /usr/bin/omp | grep -q "is owned by omp "'
fi
run apk alpine:3 'omp-*.apk' \
    'apk add --no-cache --allow-untrusted /pkg/omp-*.apk >/dev/null
apk info -W /usr/bin/omp | grep -q "is owned by omp-"'
run tar fedora:latest 'omp-*.tar.xz' \
    'tar -C / -xf /pkg/omp-*.tar.xz'

[ "$checked" -gt 0 ] || die "no package was checked"
[ "$failed" -eq 0 ] || die "$failed of $checked packages failed"
log "all $checked packages passed (a package marked NOT installed above was checked by its contents only)"
