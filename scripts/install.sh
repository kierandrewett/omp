#!/usr/bin/env bash
# Download the latest published omp release and install it the way the distro expects.
# Standalone: it needs only curl, sha256sum, and the distro's own package manager, so it can run straight from curl.
#
#   curl -fsSL https://raw.githubusercontent.com/kierandrewett/omp/main/scripts/install.sh | bash
#
# The distro comes from /etc/os-release. Each family gets its package from the release:
#   Alpine -> .apk, Fedora and RHEL family -> .rpm, Debian and Ubuntu family -> .deb, Arch family -> .pkg.tar.zst
# Anything else, or a system without root access, gets the raw binary in ~/.local/bin.
# Every download is checked against SHA256SUMS.txt before it is installed.
#
# Settings, all optional:
#   OMP_VERSION       release tag to install, for example v18.14.2-fork.7. Default: the latest release.
#   OMP_METHOD        "binary" skips the package and installs the raw glibc binary. Default: detect.
#   OMP_INSTALL_PATH  where to put the raw binary. Setting it implies OMP_METHOD=binary. Default: ~/.local/bin/omp.
#
# To install from a local build instead, use scripts/install-local.sh (just install).
set -euo pipefail
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

repo=kierandrewett/omp

die() {
    printf '[install] error: %s\n' "$*" >&2
    exit 1
}

log() {
    printf '[install] %s\n' "$*"
}

[ "$(uname -s)" = Linux ] || die "only Linux builds are published"

# Package file names differ by format, so each format has its own architecture word.
case "$(uname -m)" in
    x86_64 | amd64)
        binary=omp-linux-x64
        rpm_arch=x86_64 deb_arch=amd64 arch_arch=x86_64 apk_arch=x86_64
        ;;
    aarch64 | arm64)
        binary=omp-linux-arm64
        rpm_arch=aarch64 deb_arch=arm64 arch_arch=aarch64 apk_arch=aarch64
        ;;
    *) die "no build for $(uname -m)" ;;
esac

for tool in curl sha256sum install; do
    command -v "$tool" > /dev/null 2>&1 || die "$tool is required"
done

# ID and ID_LIKE together, lower case, so "ubuntu debian" and "cachyos arch" both match their family.
distro=""
if [ -r /etc/os-release ]; then
    distro="$(. /etc/os-release && printf '%s %s' "${ID:-}" "${ID_LIKE:-}" | tr '[:upper:]' '[:lower:]')"
fi

family() {
    local word
    for word in $distro; do
        case "$word" in
            alpine) echo apk; return ;;
            fedora | rhel | centos | rocky | almalinux) echo rpm; return ;;
            debian | ubuntu) echo deb; return ;;
            arch) echo pkg.tar.zst; return ;;
        esac
    done
}

# The raw binaries are glibc. A musl system that is not Alpine has no package, so stop instead of installing a binary
# that cannot start.
is_musl() {
    [ -e /etc/alpine-release ] || { command -v ldd > /dev/null 2>&1 && ldd --version 2>&1 | grep -qi musl; }
}

method=binary
format=""
sudo=""
if [ -z "${OMP_INSTALL_PATH:-}" ] && [ "${OMP_METHOD:-}" != binary ]; then
    format="$(family)"
    case "$format" in
        apk) tool=apk ;;
        rpm) tool=dnf ;;
        deb) tool=apt-get ;;
        pkg.tar.zst) tool=pacman ;;
        *) tool="" ;;
    esac
    if [ -z "$format" ]; then
        log "distro '${distro:-unknown}' has no package; using the raw binary"
    elif ! command -v "$tool" > /dev/null 2>&1; then
        log "$tool not found; using the raw binary"
    elif [ "$(id -u)" -eq 0 ]; then
        method=package
    elif command -v sudo > /dev/null 2>&1; then
        sudo=sudo
        method=package
    else
        log "not root and no sudo; using the raw binary"
    fi
fi

if [ "$method" = binary ] && is_musl; then
    die "this system uses musl and has no package here; the raw binary is glibc. Build from source: https://github.com/$repo"
fi

if [ -n "${OMP_VERSION:-}" ]; then
    base="https://github.com/$repo/releases/download/$OMP_VERSION"
else
    base="https://github.com/$repo/releases/latest/download"
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

fetch() {
    curl -fsSL -o "$work/$1" "$base/$1" || die "could not download $base/$1"
}

# The sums file lists every file in the release, so it also tells us the versioned package name.
fetch SHA256SUMS.txt

if [ "$method" = package ]; then
    case "$format" in
        rpm) pattern="omp-.*\\.$rpm_arch\\.rpm" ;;
        deb) pattern="omp_.*_$deb_arch\\.deb" ;;
        pkg.tar.zst) pattern="omp-.*-$arch_arch\\.pkg\\.tar\\.zst" ;;
        apk) pattern="omp-.*-$apk_arch\\.apk" ;;
    esac
    file="$(awk '{ print $2 }' "$work/SHA256SUMS.txt" | grep -E "^$pattern\$" || true)"
    [ -n "$file" ] || die "the release has no $format package for $(uname -m)"
    [ "$(printf '%s\n' "$file" | wc -l)" -eq 1 ] || die "more than one $format package matched: $file"
else
    file="$binary"
fi

log "downloading $file from ${OMP_VERSION:-the latest release}"
fetch "$file"
(cd "$work" && grep -F " $file" SHA256SUMS.txt | grep -E " \\*?$file\$" | sha256sum -c - > /dev/null) \
    || die "checksum mismatch for $file"

if [ "$method" = package ]; then
    log "installing $file with $tool${sudo:+ (through sudo)}"
    case "$format" in
        rpm) $sudo dnf install -y "$work/$file" ;;
        deb) $sudo apt-get install -y "$work/$file" ;;
        pkg.tar.zst) $sudo pacman -U --noconfirm "$work/$file" ;;
        # The apk is not signed with a key apk knows; the checksum above is what vouches for it.
        apk) $sudo apk add --no-cache --allow-untrusted "$work/$file" ;;
    esac
    log "installed $(omp --version) at $(command -v omp)"
    exit 0
fi

# Rename into place, so a running omp session keeps its old inode and is not corrupted.
target="${OMP_INSTALL_PATH:-$HOME/.local/bin/omp}"
mkdir -p "$(dirname "$target")"
install -m 755 "$work/$file" "$target.new"
mv -f "$target.new" "$target"
log "installed $("$target" --version) at $target"

case ":$PATH:" in
    *":$(dirname "$target"):"*) ;;
    *) log "$(dirname "$target") is not on your PATH" ;;
esac
