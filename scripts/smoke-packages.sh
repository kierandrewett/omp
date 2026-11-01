#!/usr/bin/env bash
# Install every package in a folder in a throwaway container of its own distro, then check that the package manager
# owns /usr/bin/omp and that the installed program reports this release and passes its own smoke test.
# Local runs and CI both call this. Containers are removed afterwards; nothing is installed on this machine.
#
# Usage: smoke-packages.sh [DIR]     default: dist/packages
# Environment: ENGINE   podman or docker (default: podman if present, else docker)
#              ONLY     comma separated formats to check, for example rpm,deb
# The images are the ones of each distro for the architecture of this machine, so an arm64 runner checks arm64.
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

run rpm fedora:latest 'omp-*.rpm' \
    'dnf install -y /pkg/omp-*.rpm >/dev/null
test "$(rpm -qf /usr/bin/omp)" = "$(rpm -qp --qf "%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}" /pkg/omp-*.rpm)"'
run deb debian:12 'omp_*.deb' \
    'apt-get install -y /pkg/omp_*.deb >/dev/null
dpkg -S /usr/bin/omp | grep -q "^omp: "'
run archlinux archlinux:latest 'omp-*.pkg.tar.zst' \
    'pacman -U --noconfirm /pkg/omp-*.pkg.tar.zst >/dev/null
pacman -Qo /usr/bin/omp | grep -q "is owned by omp "'
run apk alpine:3 'omp-*.apk' \
    'apk add --no-cache --allow-untrusted /pkg/omp-*.apk >/dev/null
apk info -W /usr/bin/omp | grep -q "is owned by omp-"'
run tar fedora:latest 'omp-*.tar.xz' \
    'tar -C / -xf /pkg/omp-*.tar.xz'

[ "$checked" -gt 0 ] || die "no package was checked"
[ "$failed" -eq 0 ] || die "$failed of $checked packages failed"
log "all $checked packages installed and ran"
