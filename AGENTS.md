# omp agent notes

Patch series for Kieran's fork of can1357/oh-my-pi. Read `README.md` first.

## Rules

* All changes to OMP go in `patches/` as patches. Never commit source into `upstream/`.
* Make and change patches in `work/src`, then run `just export`. Do not edit `patches/*.patch` by hand.
* A patch is one plain `git diff --binary` of one commit. Do not use `git format-patch`.
* When an update conflicts, rebase the patches. Never delete a patch to make it pass.
* Do not change git config. Commit with the configured identity. Do not pass `-c user.name` or `-c user.email`.
* Pass absolute paths to `git -C upstream worktree add`. A relative path resolves inside the submodule.
* `build/`, `work/` and `dist/` are ignored. Do not commit them.
* A pushed tag that starts with `v` publishes a release. Do not create or push tags, and do not publish, unless Kieran
  says so. A manual run of the release workflow is a dry run and is safe.
* A release holds only the raw binaries `omp-linux-x64` and `omp-linux-arm64` and `SHA256SUMS.txt`. Do not add distro
  packages, per-distro install paths or musl builds. `omp update` reads those two file names.
* Do not run `just install` without Kieran's say-so. It replaces the `omp` he is running.

## Upstream code rules

The patches must follow upstream style: tabs, no `any`, no `ReturnType<>`, no inline or dynamic imports,
`#private` fields, `Promise.withResolvers()`, and no wall-clock timers in tests. Run `bunx oxfmt` on touched files.
Check with `bun run check:types` in `packages/coding-agent`.

## Traps found while building

* Do not run `oxfmt` or the `edit` tool on large upstream files (`interactive-mode.ts`, `executor.ts`, `tui/src/tools/task.ts`).
  The format-on-save hook rewrites the whole file with spaces and the diff grows to tens of thousands of lines.
  Use exact-text replacement with a script that asserts each anchor occurs once, then check `git diff --stat`.
* Do not add `await import()`. Upstream bans it. A value import from a low-level module into the task graph can
  merge bundle graphs and break the binary build ("Multiple files share the same output path"). Register a callback
  instead, as `registerSubagentModelSwitcher` does.
* Run tests with the default timeout. A test that only passes with `--timeout 20000` fails in upstream's setup.
* Pass `set -o pipefail` when piping `scripts/build.sh` into `tail`, or the exit status is lost.

## Known failures on plain upstream

On v18.14.2, 26 tests in `test/task` and `test/eval` fail without any patch. Worktree tests fail because the commit
proxy blocks their git identity. The cell-syntax-error tests and some startup tests fail too. Compare against this
list before blaming a patch.
