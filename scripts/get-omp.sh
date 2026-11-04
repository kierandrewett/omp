#!/usr/bin/env bash
# Download the latest published omp binary, check it against SHA256SUMS.txt and install it.
# Standalone: it needs only curl, sha256sum and install, so it can run straight from curl.
#
#   curl -fsSL https://raw.githubusercontent.com/kierandrewett/omp/main/scripts/get-omp.sh | bash
#
# Settings, all optional:
#   OMP_VERSION       release tag to install, for example v18.14.2-fork.7. Default: the latest release.
#   OMP_INSTALL_PATH  where to put the binary. Default: ~/.local/bin/omp.
set -euo pipefail
export PATH="/usr/local/bin:/usr/bin:/bin:$PATH"

repo=kierandrewett/omp

die() {
    printf '[get-omp] error: %s\n' "$*" >&2
    exit 1
}

log() {
    printf '[get-omp] %s\n' "$*"
}

[ "$(uname -s)" = Linux ] || die "only Linux builds are published"

case "$(uname -m)" in
    x86_64 | amd64) name=omp-linux-x64 ;;
    aarch64 | arm64) name=omp-linux-arm64 ;;
    *) die "no binary for $(uname -m)" ;;
esac

# The published raw binaries are glibc. Alpine and other musl systems use the apk from the release page.
if [ -e /etc/alpine-release ] || { command -v ldd > /dev/null 2>&1 && ldd --version 2>&1 | grep -qi musl; }; then
    die "this system uses musl; install the .apk from https://github.com/$repo/releases/latest"
fi

for tool in curl sha256sum install; do
    command -v "$tool" > /dev/null 2>&1 || die "$tool is required"
done

if [ -n "${OMP_VERSION:-}" ]; then
    base="https://github.com/$repo/releases/download/$OMP_VERSION"
else
    base="https://github.com/$repo/releases/latest/download"
fi

target="${OMP_INSTALL_PATH:-$HOME/.local/bin/omp}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

log "downloading $name from ${OMP_VERSION:-the latest release}"
curl -fsSL -o "$work/$name" "$base/$name" || die "could not download $base/$name"
curl -fsSL -o "$work/SHA256SUMS.txt" "$base/SHA256SUMS.txt" || die "could not download $base/SHA256SUMS.txt"

(cd "$work" && grep " $name\$" SHA256SUMS.txt | sha256sum --check --quiet -) || die "checksum mismatch for $name"

# Rename into place, so a running omp session keeps its old inode and is not corrupted.
mkdir -p "$(dirname "$target")"
install -m 755 "$work/$name" "$target.new"
mv -f "$target.new" "$target"
log "installed $("$target" --version) at $target"

case ":$PATH:" in
    *":$(dirname "$target"):"*) ;;
    *) log "$(dirname "$target") is not on your PATH" ;;
esac
