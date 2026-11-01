#!/usr/bin/env bash
# Build the patched Linux binary from the pinned upstream commit plus the patch series.
# Output: dist/omp-linux-<arch> and dist/SHA256SUMS.txt. Does not touch work/src.
# The architecture is this machine's (x64 or arm64). TARGET_ARCH overrides it.
# NATIVES picks how the Rust addon is made:
#   host      (default) Cargo build for this machine, no Bazel
#   bazel     Bazel, as release CI does: both addons for x64, one for arm64. NATIVES_TARGETS overrides the list
#   prebuilt  copy this arch's pi_natives.linux-*.node from NATIVES_DIR; only for the same upstream version
# NATIVES_ONLY=DIR stops after the addons, copies every addon of this run to DIR, and builds no binary. CI uses it
# to cross-build the arm64 addon on an x64 runner, where Bazel is known to work.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

pinned="$(pinned_commit)"
eval "$("$root/scripts/release-info.sh")"
tag="$upstream_tag"

case "${TARGET_ARCH:-$(uname -m)}" in
    x86_64 | amd64 | x64) arch=x64 ;;
    aarch64 | arm64) arch=arm64 ;;
    *) die "unsupported architecture '${TARGET_ARCH:-$(uname -m)}'; use x64 or arm64" ;;
esac
binary_name="omp-linux-$arch"

if [ -e "$build_tree" ]; then
    git -C "$upstream" worktree remove --force "$build_tree"
fi
mkdir -p "$(dirname "$build_tree")" "$dist"
git -C "$upstream" worktree add --detach "$build_tree" "$pinned" >/dev/null
"$root/scripts/apply-patches.sh" "$build_tree"

cd "$build_tree"

# Upstream's compiled binary refuses to start when the Bun that built it is older than `packageManager` asks
# for. Keep the system Bun as it is and build with a private copy of the required version when it is older.
required_bun="$(sed -nE 's/.*"packageManager": *"bun@>=([0-9.]+)".*/\1/p' package.json)"
if [ -n "$required_bun" ] && [ "$(printf '%s\n%s\n' "$required_bun" "$(bun --version)" | sort -V | head -n 1)" != "$required_bun" ]; then
    log "Bun $(bun --version) is older than $required_bun; using a private copy"
    npm install --prefix "$root/build/bun" "bun@$required_bun" >/dev/null
    export PATH="$root/build/bun/node_modules/.bin:$PATH"
fi
log "building with Bun $(bun --version)"

log "installing dependencies"
# Upstream's prepare script checks generated viewer metadata and fails on some tags.
bun install --frozen-lockfile --ignore-scripts
python3 "$root/scripts/stamp-version.py" "$build_tree" "$tag" "$fork_tag"

# Upstream commits a hash of its bundled export viewer. The hash depends on the exact Bun bundler output,
# so it differs on any other Bun version and both `--check` runs then fail with "metadata is stale".
# Regenerate it here, in the throwaway tree. CI=true would force check mode, so unset it for this step.
log "regenerating export viewer metadata"
env -u CI bun run --cwd packages/collab-web gen:export-viewer

# Natives take about ten minutes to build, so keep them. The key covers everything that decides the result:
# the upstream commit, the build mode, the staged (patched) contents of the native sources, and the Rust
# toolchain. A patch that touches the Rust sources therefore gets its own entry.
natives_mode="${NATIVES:-host}"
natives_sources="$(git ls-files --stage -- crates packages/natives Cargo.toml Cargo.lock | sha256sum | cut -c1-16)"
natives_toolchain="$({ rustc --version --verbose 2>/dev/null || true; } | sha256sum | cut -c1-8)"
natives_key="$root/build/natives-cache/${pinned:0:10}-$arch-$natives_mode-$natives_sources-$natives_toolchain"
if [ "$natives_mode" != prebuilt ] && compgen -G "$natives_key/pi_natives.*.node" >/dev/null; then
    log "using cached natives from $natives_key"
    cp "$natives_key"/pi_natives.*.node packages/natives/native/
else
    case "$natives_mode" in
        host)
            # Local Cargo build of the addon for this machine. No Bazel needed.
            log "building natives for this host"
            bun scripts/bazel-natives.ts host
            ;;
        bazel)
            # Same as release CI. x64 has a modern and a baseline addon, so the binary runs on any x64 CPU.
            command -v bazel >/dev/null || {
                log "installing Bazelisk"
                npm install --prefix "$root/build/bazelisk" @bazel/bazelisk >/dev/null
                export PATH="$root/build/bazelisk/node_modules/.bin:$PATH"
            }
            log "building natives with Bazel"
            if [ -n "${NATIVES_TARGETS:-}" ]; then
                read -r -a natives_targets <<<"$NATIVES_TARGETS"
            elif [ "$arch" = x64 ]; then
                natives_targets=(linux-x64-baseline linux-x64-modern)
            else
                natives_targets=(linux-arm64)
            fi
            for target in "${natives_targets[@]}"; do
                bun scripts/bazel-natives.ts "$target"
            done
            ;;
        prebuilt)
            [ -n "${NATIVES_DIR:-}" ] || die "NATIVES=prebuilt needs NATIVES_DIR"
            log "using prebuilt natives from $NATIVES_DIR"
            compgen -G "$NATIVES_DIR/pi_natives.linux-$arch*.node" >/dev/null || die "no $arch addon in $NATIVES_DIR"
            cp "$NATIVES_DIR"/pi_natives.linux-"$arch"*.node packages/natives/native/
            ;;
        *)
            die "NATIVES must be host, bazel or prebuilt"
            ;;
    esac
    if [ "$natives_mode" != prebuilt ]; then
        mkdir -p "$natives_key"
        cp packages/natives/native/pi_natives.*.node "$natives_key/"
    fi
fi

if [ -n "${NATIVES_ONLY:-}" ]; then
    mkdir -p "$NATIVES_ONLY"
    cp packages/natives/native/pi_natives.*.node "$NATIVES_ONLY/"
    log "addons for $arch copied to $NATIVES_ONLY"
    ls -l "$NATIVES_ONLY" >&2
    exit 0
fi

log "building binary"
RELEASE_TARGETS="linux-$arch" bun run ci:release:build-binaries

bin="packages/coding-agent/binaries/$binary_name"
[ -s "$bin" ] || die "build produced no binary"
[ "$("./$bin" --version)" = "omp/${fork_tag#v}" ] || die "binary version is '$("./$bin" --version)', expected omp/${fork_tag#v}"
install -m 755 "$bin" "$dist/$binary_name"
(cd "$dist" && sha256sum "$binary_name" > SHA256SUMS.txt)
log "built $dist/$binary_name ($fork_tag)"
