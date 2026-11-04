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
|`0009-musl-x64-modern-addon`|Adds a `linux-musl-x64-modern` Bazel target, which upstream lacks, so musl x64 has the same two addon variants as glibc.|
|`0010-anthropic-sequential-accounts`|Anthropic accounts are used one at a time until one is blocked or spent. `retry.accountMode` is `sequential` (default) or `balanced`.|
|`0011-status-line-usage-bar-and-account-labels`|Adds a `usage_bar` status-line segment to the default preset. The model shows its account, such as `Anthropic (B) > Sonnet 5.5`.|
|`0012-subagent-shelf-and-viewer-fixes`|Colours the subagent counter, shows tokens on the completion line, fixes `.` in a busy subagent, and ends very long 429 waits cleanly.|
|`0013-mcp-elicitation-ask-dialog`|A server's approval request shows in the same dialog as the `ask` tool. Anything but an explicit Accept is a cancel.|
|`0014-task-routing-preferences`|Adds `task.routingPreferences`: your own text on which work suits which model, for the automatic subagent choice. Empty by default.|
|`0015-status-line-usage-window`|`usage_bar` shows weekly usage by default. `statusLine.usageWindow` picks weekly, 5-hour or the worst window.|
|`0016-status-line-weekly-only`|In weekly mode `usage_bar` shows only the 7-day window, or no bar if the provider has none.|
|`0017-task-never-inherit-parent-model`|Subagents never use the parent's model or switch models. One alias is picked without the judge. A failed choice stops, with no fallback.|
|`0018-no-billable-automatic-model`|Automatic choices never use a model that bills real money: startup model, tiers, aliases, judge, helpers. Naming a model yourself still works.|

Upstream gates the per-call `model` field behind `task.perCallModel`, and the default is `off`. Set it to `on` in
`~/.omp/agent/config.yml` to let agents pass `@haiku`, `$$` and similar. Automatic judge routing works without it.

## Download the latest release

One script downloads the latest release, checks it against `SHA256SUMS.txt` and installs it:

```sh
curl -fsSL https://raw.githubusercontent.com/kierandrewett/omp/main/scripts/install.sh | bash
```

It reads `/etc/os-release` and installs the package your distro uses, for your architecture (x86_64 or arm64):

|Distro|Installs|
|---|---|
|Fedora, RHEL family|the `.rpm`, with `dnf`|
|Debian, Ubuntu family|the `.deb`, with `apt-get`|
|Arch family|the `.pkg.tar.zst`, with `pacman -U`|
|Alpine|the `.apk`, with `apk add`|
|Anything else, or no root and no `sudo`|the raw glibc binary in `~/.local/bin/omp`|

Package installs use `sudo` when you are not root.

* Set `OMP_VERSION=v18.14.2-fork.7` to pin a release.
* Set `OMP_METHOD=binary` to skip the package and install the raw binary.
* Set `OMP_INSTALL_PATH` to choose where the raw binary goes. It implies `OMP_METHOD=binary`.

A musl system that is not Alpine has no package, and the script stops. After an install, `omp update` reads the same
releases and checks the same `SHA256SUMS.txt`. `just install` still installs a local build, through
`scripts/install-local.sh`.

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
|`bazel`|The Linux addons through Bazel, as release CI does: baseline and modern for x64, one for arm64.|
|`prebuilt`|Copy `pi_natives.*.node` from `NATIVES_DIR`. Use only for the same upstream version.|

`LIBC` picks the C library of the binary: `glibc` (default) or `musl`. Alpine runs musl, so only a musl binary gets an apk.
A musl build uses upstream's `linux-musl-<arch>` binary targets and addons, which Bazel cross-builds on a glibc machine:

```sh
LIBC=musl NATIVES=bazel scripts/build.sh     # dist/omp-linux-musl-<arch>
```

* A `NATIVES=prebuilt` musl build needs its own `NATIVES_DIR`, because upstream's musl addons keep the file names of the glibc ones.
* `scripts/build.sh` checks what each addon links to and stops on the wrong one.
* `NATIVES=host` works only for the C library of the machine.
* `build.sh` does not run a musl binary on a glibc machine.
* The glibc names `omp-linux-x64` and `omp-linux-arm64` do not change.

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

|Format|File|Binary|Checked on|
|---|---|---|---|
|rpm|`omp-18.14.2-4.x86_64.rpm`|glibc|`fedora:latest`|
|deb|`omp_18.14.2-4_amd64.deb`|glibc|`debian:12`|
|archlinux|`omp-18.14.2-4-x86_64.pkg.tar.zst`|glibc|`archlinux:latest`|
|apk|`omp-18.14.2-r4-x86_64.apk`|musl|`alpine:3`|
|tar|`omp-18.14.2-amd64.tar.xz`|glibc|`fedora:latest`|

The package version is the upstream version and the release is the fork revision, so `18.14.2` with revision `4` is
`omp-18.14.2-4` and sorts above revision 3. arm64 packages carry `arm64` or `aarch64` in the same places.

pkgsmith is not on crates.io, and its only tag (v0.1.0) is older than the script design this repo uses. So
`scripts/get-pkgsmith.sh` builds it from the commit in `scripts/pkgsmith-commit`. Change that file to move to a newer
pkgsmith.

**The apk is a musl build.** The glibc binary does not run on Alpine. Plain Alpine reports `not found`, and with `gcompat`
it fails with `__pthread_key_create: symbol not found`. So the apk holds its own musl binary, and the other four packages
hold the glibc one.

* `scripts/package.sh` reads the C library and the architecture from the ELF headers of the binary in the prefix. A musl
  binary gets only the apk. A glibc binary gets the other four.
* The apk depends on `libstdc++` and `libgcc`, because Bun's musl binaries link to them dynamically. Upstream's own
  Alpine smoke test installs the same two.
* pkgsmith names an apk `omp-18.14.2-r4.apk`, with no architecture. `scripts/package.sh build` renames it to
  `omp-18.14.2-r4-x86_64.apk` (`aarch64` on arm64), so one release can hold both. `just plan` still shows the pkgsmith
  name. apk reads the package name and version from inside the file.

**`omp update` and packages.** The updater treats a plain file at `/usr/bin/omp` as a standalone binary and would try
to replace it. Update a package install with the package manager. Making `omp update` stand down for package-owned
paths needs a new patch.

## Releases

A tag that starts with `v` runs `.github/workflows/release.yml`. It builds omp for amd64 and arm64, each as a glibc and
a musl binary, writes the packages, installs each package in a container of its distro (the apk in Alpine), and
publishes one release that holds:

* the raw glibc binaries `omp-linux-x64` and `omp-linux-arm64`, which `omp update` reads,
* every package: rpm, deb, Arch, apk and tar, for both architectures (ten files),
* `SHA256SUMS.txt` for all of them.

The raw musl binaries are not published. `omp update` reads the glibc names only, so those do not change.

The tag must equal the release the commit describes, which is the pinned upstream tag plus `revision`, for example
`v18.14.2-fork.2`. `scripts/release-info.sh` prints it. Raise `revision` and commit before you push the tag. The run
stops when the tag differs or when a release for it exists, and a published release is never overwritten.

```sh
scripts/release-info.sh          # fork_tag=v18.14.2-fork.4 after you raise revision to 4
git tag v18.14.2-fork.4 && git push origin v18.14.2-fork.4
```

A manual run from the Actions tab is a dry run. It builds everything, checks the packages, and uploads the files and
`SHA256SUMS.txt` as workflow artifacts. It never creates a release or a tag, even on a tag ref.

How the release builds:

* The glibc addons for both architectures are cross-built on one x64 runner with Bazel, as upstream does, so the binary
  keeps a low glibc floor.
* The musl addons are cross-built the same way in a parallel job and their own artifact, because they share file names
  with the glibc addons.
* Each architecture and C library then builds its own binary on a runner of that architecture (`ubuntu-24.04` and
  `ubuntu-24.04-arm`) and checks it there. The musl packages are installed in `alpine:3`.
* A local `just build` uses `NATIVES=host` and makes only this machine's addon. Install it here and do not publish it.

## Licence

The patches contain lines of [oh-my-pi](https://github.com/can1357/oh-my-pi), which is MIT. `NOTICE.md` carries its
licence text. The files added in this repository have no licence of their own yet.

## Checked, and not checked

Every run of the release workflow checks this on real runners (amd64 on `ubuntu-24.04`, arm64 on `ubuntu-24.04-arm`):

* Each package installs in a container of its distro: `fedora:latest` for the rpm and the tar, `debian:12` for the deb,
  `archlinux:latest` for the Arch package and `alpine:3` for the apk.
* The package manager owns `/usr/bin/omp`, and `omp --version` and `omp --smoke-test` pass.
* On x64 the smoke test runs again with `PI_NATIVE_VARIANT=modern` and with `baseline`. The check needs the matching
  addon to be unpacked under `~/.omp/natives`. `--smoke-test` exits 1 when an addon cannot load, so a pass means that
  addon loaded, and both embedded addons are in each x64 package.
* On arm64 the Arch package is checked by its contents only, because Arch Linux has no official arm64 image.
* The collect step stops unless the release holds two files of each of the five formats.

The glibc addons that CI builds need only libraries from glibc and symbols up to glibc 2.17, on both architectures. A
local `just build` makes a different addon. It needs glibc 2.39 and `libgcc_s`, so a locally built package will not load
its addon on an older distro.

Not checked:

* The publish step. A dry run never runs it. Only a pushed tag does.
* The modern musl x64 addon comes from patch 0009. Upstream does not build or test it. Only the check above covers it.
* Alpine versions other than the current `alpine:3` tag, and any architecture other than amd64 and arm64.
* `omp update` on Alpine. An apk install is updated with apk, as the other packages are updated with their managers.
