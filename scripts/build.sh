#!/usr/bin/env bash
# Build the patched Linux x64 binary from the pinned upstream commit plus the patch series.
# Output: dist/omp-linux-x64 and dist/SHA256SUMS.txt. Does not touch work/src.
# NATIVES picks how the Rust addon is made:
#   host      (default) Cargo build for this machine, no Bazel
#   bazel     both Linux x64 addons through Bazel, as release CI does
#   prebuilt  copy pi_natives.*.node from NATIVES_DIR; only for the same upstream version
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

pinned="$(pinned_commit)"
tag="$(git -C "$upstream" describe --tags --exact-match "$pinned" 2>/dev/null)" || die "pinned upstream commit is not a release tag"
[[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "pinned tag is not a stable release: $tag"
revision="$(tr -d '[:space:]' < "$root/revision")"
[[ "$revision" =~ ^[1-9][0-9]*$ ]] || die "revision must be a positive integer"
fork_tag="$tag-fork.$revision"

if [ -e "$build_tree" ]; then
    git -C "$upstream" worktree remove --force "$build_tree"
fi
mkdir -p "$(dirname "$build_tree")" "$dist"
git -C "$upstream" worktree add --detach "$build_tree" "$pinned" >/dev/null
"$root/scripts/apply-patches.sh" "$build_tree"

cd "$build_tree"
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
natives_toolchain="$(rustc --version --verbose 2>/dev/null | sha256sum | cut -c1-8)"
natives_key="$root/build/natives-cache/${pinned:0:10}-$natives_mode-$natives_sources-$natives_toolchain"
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
            # Same as release CI: both Linux x64 addons through Bazel.
            command -v bazel >/dev/null || {
                log "installing Bazelisk"
                npm install --prefix "$root/build/bazelisk" @bazel/bazelisk >/dev/null
                export PATH="$root/build/bazelisk/node_modules/.bin:$PATH"
            }
            log "building natives with Bazel"
            bun scripts/bazel-natives.ts linux-x64-baseline
            bun scripts/bazel-natives.ts linux-x64-modern
            ;;
        prebuilt)
            [ -n "${NATIVES_DIR:-}" ] || die "NATIVES=prebuilt needs NATIVES_DIR"
            log "using prebuilt natives from $NATIVES_DIR"
            cp "$NATIVES_DIR"/pi_natives.*.node packages/natives/native/
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

log "building binary"
RELEASE_TARGETS=linux-x64 bun run ci:release:build-binaries

bin="packages/coding-agent/binaries/omp-linux-x64"
[ -s "$bin" ] || die "build produced no binary"
[ "$("./$bin" --version)" = "omp/${fork_tag#v}" ] || die "binary version is '$("./$bin" --version)', expected omp/${fork_tag#v}"
install -m 755 "$bin" "$dist/omp-linux-x64"
(cd "$dist" && sha256sum omp-linux-x64 > SHA256SUMS.txt)
log "built $dist/omp-linux-x64 ($fork_tag)"
