#!/usr/bin/env bash
# Download the latest published omp release binary and install it. The binary is the only thing a release holds.
# Standalone: it needs only curl, sha256sum and install, so it can run straight from curl.
#
#   curl -fsSL https://raw.githubusercontent.com/kierandrewett/omp/main/scripts/install.sh | bash
#
# The download is checked against SHA256SUMS.txt before it is installed.
#
# Settings, all optional:
#   OMP_VERSION       release tag to install, for example v18.14.2-fork.10. Default: the latest release.
#   OMP_INSTALL_PATH  where to put the binary. Default: ~/.local/bin/omp.
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

case "$(uname -m)" in
    x86_64 | amd64) file=omp-linux-x64 ;;
    aarch64 | arm64) file=omp-linux-arm64 ;;
    *) die "no build for $(uname -m)" ;;
esac

for tool in curl sha256sum install; do
    command -v "$tool" > /dev/null 2>&1 || die "$tool is required"
done

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

fetch SHA256SUMS.txt
log "downloading $file from ${OMP_VERSION:-the latest release}"
fetch "$file"
(cd "$work" && grep -E " \\*?$file\$" SHA256SUMS.txt | sha256sum -c - > /dev/null) \
    || die "checksum mismatch for $file"

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
