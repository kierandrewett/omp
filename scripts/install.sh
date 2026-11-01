#!/usr/bin/env bash
# Install dist/omp-linux-x64 as ~/.local/bin/omp after checking its checksum.
# The running binary is replaced by rename, so a live session is not corrupted.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

[ -s "$dist/omp-linux-x64" ] || die "nothing built; run scripts/build.sh first"
(cd "$dist" && sha256sum --check --quiet SHA256SUMS.txt) || die "checksum mismatch in $dist"
target="${OMP_INSTALL_PATH:-$HOME/.local/bin/omp}"
mkdir -p "$(dirname "$target")"
install -m 755 "$dist/omp-linux-x64" "$target.new"
mv -f "$target.new" "$target"
log "installed $("$target" --version) at $target"
