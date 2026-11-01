# omp

Kieran's patched build of [can1357/oh-my-pi](https://github.com/can1357/oh-my-pi).

This repo holds no upstream source. It holds a patch series, and `upstream/` is a submodule pinned to one
upstream release tag. To build, the scripts apply the series to that tag and compile the result.

## Patches

The order is in `patches/series`. Each patch is one plain `git diff --binary`.

|Patch|What it does|
|---|---|
|`0001-task-model-selection`|Pick a model role per subagent. With no `model`, the Jev judge chooses a configured role. The result shows the route.|
|`0002-fork-updater`|`omp update` reads the fork's GitHub releases and checks `SHA256SUMS.txt`.|
|`0003-mcp-form-elicitation`|Answer MCP `elicitation/create` with a dialog. No answer means cancel, never accept.|
|`0004-task-model-role-prompting`|The task tool lists your roles as `@role`. Agents pass the role when you name a model, and use `ask` when they cannot tell.|
|`0005-task-model-price-tiers`|`model` can be `$` to `$$$$`. Tiers are quarters of the price across all loaded chat models. Usage from `stats.db` breaks ties, weighted exact model over family over provider. `$$$$` is very rare.|
|`0006-subagent-shelf-usage`|Each row in the pinned subagent shelf shows that subagent's total tokens and API cost.|
|`0007-task-model-switch`|Change a running subagent's model mid-run: `write proc://<id>/model` for the main agent (role, tier or exact ID), and `/switch` inside the subagent view for you.|
|`0008-background-tasks-shelf`|A `Background tasks` shelf above `Subagents` lists running backgrounded bash commands, eval cells and services, with id, command and elapsed time. `display.pinnedJobs` sets it to `collapsed`, `full` or `off`.|

Upstream gates the per-call `model` field behind `task.perCallModel`, and the default is `off`. Set it to `on` in
`~/.omp/agent/config.yml` to let agents pass `@haiku`, `$$` and similar. Automatic judge routing works without it.

## Use

You need `git`, `bun`, `just`, `cargo` and `python3`.

```sh
git clone --recurse-submodules git@github.com:kierandrewett/omp.git
cd omp
just build      # dist/omp-linux-x64 and dist/SHA256SUMS.txt
just install    # ~/.local/bin/omp
```

`just build` works in `build/src`, a throwaway worktree. It never changes `upstream/` or `work/`.

`NATIVES` picks how the Rust addon is made:

|Value|Meaning|
|---|---|
|`host` (default)|Cargo build for this machine. No Bazel.|
|`bazel`|Both Linux x64 addons through Bazel, as release CI does.|
|`prebuilt`|Copy `pi_natives.*.node` from `NATIVES_DIR`. Use only for the same upstream version.|

The build uses the Bun version upstream asks for in `packageManager`. If the system Bun is older, `build/bun` gets a private copy and the system Bun stays as it is.

`revision` holds the fork revision. The binary reports `X.Y.Z-fork.N`. Raise `N` when you ship changed patches for an
upstream version you already shipped.

## Change a patch

```sh
just work       # work/src: upstream tag plus one commit per patch
cd work/src     # edit, test, then commit (a new commit becomes a new patch)
cd ../..
just export     # rewrite patches/ and patches/series from the commits
```

The commit subject names the patch file. `task model selection` becomes `0001-task-model-selection.patch`.
Use `git commit --fixup <commit>` and `git rebase -i --autosquash` to change an earlier patch.
`just export` refuses a dirty work tree.

Tests need the Rust addon. In a fresh work tree, run `bun install --frozen-lockfile --ignore-scripts`, then
`bun scripts/bazel-natives.ts host` inside `work/src`. Upstream's `prepare` script fails on some tags, which is
why the scripts pass `--ignore-scripts`.

## Move to a new upstream release

```sh
just update          # newest stable tag, or: just update v18.15.0
```

This moves the submodule and rebuilds `work/src`. A patch that no longer applies stops the run with conflict
markers in `work/src`. Fix them, commit, run `just export`, then `git add upstream patches` and commit.
Never drop a patch to make an update pass.

## Packages

[pkgsmith](https://github.com/kierandrewett/pkgsmith) writes the packages. It builds nothing: `scripts/install-prefix.sh`
puts the built binary in `build/prefix` (a folder laid out like an installed system), and `pkgsmith.star` describes the
packages made from it. One script writes every format from the same prefix.

```sh
just build              # dist/omp-linux-<arch>
just prefix             # build/prefix/usr/bin/omp and the third-party notice
just plan               # which packages, and what each one carries
just package            # dist/packages
just smoke-packages     # install each one in a throwaway container and run omp (podman or docker)
```

|Format|File|Checked on|
|---|---|---|
|rpm|`omp-18.14.2-2.x86_64.rpm`|`fedora:latest`|
|deb|`omp_18.14.2-2_amd64.deb`|`debian:12`|
|archlinux|`omp-18.14.2-2-x86_64.pkg.tar.zst`|`archlinux:latest`|
|tar|`omp-18.14.2-amd64.tar.xz`|`fedora:latest`|

The package version is the upstream version and the release is the fork revision, so `18.14.2` with revision `2` is
`omp-18.14.2-2` and sorts above revision 1. arm64 packages carry `arm64` or `aarch64` in the same places.

pkgsmith is not on crates.io, and its only tag (v0.1.0) is older than the script design this repo uses. So
`scripts/get-pkgsmith.sh` builds it from the commit in `scripts/pkgsmith-commit`. Change that file to move to a newer
pkgsmith.

**No apk for the glibc build.** The binary links to glibc, and Alpine has musl. On plain Alpine it reports `not found`.
With `gcompat` it fails with `__pthread_key_create: symbol not found`. `scripts/package.sh` reads the C library and the
architecture from the ELF headers of the binary in the prefix, and writes an apk only for a binary whose interpreter is
musl. Then it writes only the apk. That path was checked with a stand-in musl binary, not with a musl build of omp.
Upstream builds musl binaries (`linux-musl-x64` and `linux-musl-arm64`, with `linux-musl-x64-baseline` and
`linux-musl-arm64` addons). Adding them here means two more addon builds, a `LIBC` dimension in `scripts/build.sh`, and
an Alpine install check. They are not part of this repo yet.

**`omp update` and packages.** The updater treats a plain file at `/usr/bin/omp` as a standalone binary and would try
to replace it. Update a package install with the package manager. Making `omp update` stand down for package-owned
paths needs a new patch.

## Releases

A tag that starts with `v` runs `.github/workflows/release.yml`. It builds omp for amd64 and arm64, writes the
packages, installs each package in a container of its distro, and publishes one release that holds:

* the raw binaries `omp-linux-x64` and `omp-linux-arm64`, which `omp update` reads,
* every package,
* `SHA256SUMS.txt` for all of them.

The tag must equal the release the commit describes, which is the pinned upstream tag plus `revision`, for example
`v18.14.2-fork.2`. `scripts/release-info.sh` prints it. Raise `revision` and commit before you push the tag. The run
stops when the tag differs or when a release for it exists, and a published release is never overwritten.

```sh
scripts/release-info.sh          # fork_tag=v18.14.2-fork.3 after you raise revision to 3
git tag v18.14.2-fork.3 && git push origin v18.14.2-fork.3
```

A manual run from the Actions tab is a dry run. It builds everything, checks the packages, and uploads the files and
`SHA256SUMS.txt` as workflow artifacts. It never creates a release or a tag, even on a tag ref.

The addons for both architectures are cross-built on one x64 runner with Bazel, as upstream does, so the binary keeps a
low glibc floor. Then each architecture builds its own binary on its own runner (`ubuntu-24.04` and
`ubuntu-24.04-arm`) and checks it there. A local `just build` uses `NATIVES=host` and makes only this machine's addon, so
install it here but do not publish it.

## Licence

The patches contain lines of [oh-my-pi](https://github.com/can1357/oh-my-pi), which is MIT. `NOTICE.md` carries its
licence text. The files added in this repository have no licence of their own yet.

## Checked, and not checked

Checked in a dry run of the release workflow on real runners (amd64 on `ubuntu-24.04`, arm64 on `ubuntu-24.04-arm`):
both binaries build, the rpm, deb and tar install in a container of their distro and pass `omp --version` and
`omp --smoke-test`, and the Arch package is checked by its contents on arm64 (Arch Linux has no official arm64 image).
The addons built by CI need only glibc (`libc`, `libm`, `libpthread`, `libdl`, `libutil`) and symbols up to glibc 2.17
on both architectures. A local `just build` makes a different addon: it needs glibc 2.39 and `libgcc_s`, so a locally
built package will not load its addon on an older distro.

Not checked:

* The publish step, because no tag has been pushed. It has never run.
* A musl build and an apk. No apk is written for the glibc build, and omp on Alpine has not been tested. The apk path was
  only exercised for its format, with a busybox stand-in.
* Whether `--smoke-test` loads the native addon. The container checks show that the binary starts and reports its version.
