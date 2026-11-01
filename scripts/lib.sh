#!/usr/bin/env bash
# Shared helpers. Source this file; do not run it.
# Plain rustup cargo first: the mbx cache shim in PATH breaks crate build scripts that call rustc.
export PATH="$HOME/.cargo/bin:$HOME/.local/bin:$HOME/.npm-global/bin:$PATH"

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
upstream="$root/upstream"
patch_dir="$root/patches"
series="$patch_dir/series"
work="$root/work/src"
build_tree="$root/build/src"
dist="$root/dist"

log() {
    printf '[omp] %s\n' "$*" >&2
}

die() {
    printf '[omp] error: %s\n' "$*" >&2
    exit 1
}

# The upstream commit the submodule pointer records (read from the index, so it works before the
# first commit). Patches are made against this commit.
pinned_commit() {
    git -C "$root" ls-files --stage upstream | awk 'NR == 1 { print $2 }'
}

# The architecture the build and the packages are for: x64 or arm64. This machine's, unless TARGET_ARCH says otherwise.
target_arch() {
    case "${TARGET_ARCH:-$(uname -m)}" in
        x86_64 | amd64 | x64) printf 'x64\n' ;;
        aarch64 | arm64) printf 'arm64\n' ;;
        *) die "unsupported architecture '${TARGET_ARCH:-$(uname -m)}'; use x64 or arm64" ;;
    esac
}

# The C library the build and the packages are for: glibc or musl. glibc unless LIBC says otherwise. musl is what Alpine
# runs, so a musl build is the one that gets an apk (see pkgsmith.star).
target_libc() {
    case "${LIBC:-glibc}" in
        glibc | musl) printf '%s\n' "${LIBC:-glibc}" ;;
        *) die "unsupported LIBC '$LIBC'; use glibc or musl" ;;
    esac
}

# The name upstream gives the binary of the architecture ($1: x64 or arm64) and the C library ($2): omp-linux-x64 for
# glibc and omp-linux-musl-x64 for musl. The glibc names are the ones `omp update` reads, so they do not change.
binary_name() {
    if [ "$2" = musl ]; then printf 'omp-linux-musl-%s\n' "$1"; else printf 'omp-linux-%s\n' "$1"; fi
}

# The C library an ELF program was built for, read from its program interpreter: glibc or musl. A static program
# has no interpreter, so its library cannot be told and this stops instead of guessing.
elf_libc() {
    local interpreter
    interpreter="$(readelf -l "$1" 2>/dev/null | sed -n 's/.*Requesting program interpreter: \(.*\)]/\1/p')"
    case "$interpreter" in
        *ld-musl*) printf 'musl\n' ;;
        *ld-linux*) printf 'glibc\n' ;;
        *) die "cannot tell the C library of $1 (program interpreter '${interpreter:-none}')" ;;
    esac
}

# The C library of this machine, read from its shell: Alpine's /bin/sh is a musl program.
host_libc() {
    elf_libc "$(readlink -f /bin/sh)"
}

# Whether a binary for architecture $1 (x64 or arm64) and C library $2 runs on this machine.
runs_here() {
    [ "$1" = "$(TARGET_ARCH='' target_arch)" ] && [ "$2" = "$(host_libc)" ]
}

# The C library an addon (a shared library) links to, from the libraries it needs: glibc, musl, or unknown when it names
# neither. Upstream's musl addons keep the file names of the glibc ones, so the name cannot tell them apart.
addon_libc() {
    local needed
    needed="$(readelf -d "$1" 2>/dev/null | sed -n 's/.*Shared library: \[\(.*\)\]/\1/p')"
    # A musl shared library names the C library libc.so (musl's loader provides it), or libc.musl-<arch>.so.1 in some
    # builds. Upstream's Bazel-built musl addons list libc.so, checked on the addons of the fork.4 release run.
    if grep -Eq '^(libc\.so|libc\.musl-.*)$' <<<"$needed"; then
        printf 'musl\n'
    elif grep -qx 'libc\.so\.6' <<<"$needed"; then
        printf 'glibc\n'
    else
        printf 'unknown\n'
    fi
}

# The architecture an ELF program was built for, in the names of the packages: amd64 or arm64.
elf_arch() {
    local machine
    machine="$(readelf -h "$1" 2>/dev/null | sed -n 's/^ *Machine: *//p')"
    case "$machine" in
        *X86-64*) printf 'amd64\n' ;;
        *AArch64*) printf 'arm64\n' ;;
        *) die "cannot tell the architecture of $1 (machine '${machine:-unknown}')" ;;
    esac
}

# Where the upstream submodule is cloned from.
upstream_url() {
    git config -f "$root/.gitmodules" submodule.upstream.url
}

# The stable release tag (vX.Y.Z) that points at the pinned commit. Uses the local submodule when it has the
# tag, and asks the remote when it does not: CI fetches only the pinned commit, with no tags.
upstream_tag() {
    local pinned tag
    pinned="$(pinned_commit)"
    tag="$(git -C "$upstream" describe --tags --exact-match "$pinned" 2>/dev/null || true)"
    if [ -z "$tag" ]; then
        tag="$(git ls-remote --tags "$(upstream_url)" 2>/dev/null |
            awk -v commit="$pinned" '$1 == commit { name = $2; sub("refs/tags/", "", name); sub(/\^\{\}$/, "", name); print name }' |
            grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -n 1 || true)"
    fi
    printf '%s\n' "$tag"
}

# Print the patch names from the series file, one per line. Fails on a bad or missing entry.
series_patches() {
    [ -f "$series" ] || die "missing patch series: $series"
    local patch seen=" "
    while IFS= read -r patch || [ -n "$patch" ]; do
        [[ -z "$patch" || "$patch" == \#* ]] && continue
        [[ "$patch" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*\.patch$ ]] || die "invalid patch name: $patch"
        [[ "$seen" != *" $patch "* ]] || die "duplicate patch: $patch"
        [ -s "$patch_dir/$patch" ] || die "missing or empty patch: $patch"
        seen+="$patch "
        printf '%s\n' "$patch"
    done < "$series"
}
