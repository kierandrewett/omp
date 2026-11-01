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

## Not here yet

* A GitHub Actions release workflow. The fork's updater still reads releases from `kierandrewett/oh-my-pi`.
* Packages from pkgsmith. They wait for pkgsmith 0.1.0.
