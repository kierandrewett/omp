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
* Do not run `just install` without Kieran's say-so. It replaces the `omp` he is running.

## Upstream code rules

The patches must follow upstream style: tabs, no `any`, no `ReturnType<>`, no inline or dynamic imports,
`#private` fields, `Promise.withResolvers()`, and no wall-clock timers in tests. Run `bunx oxfmt` on touched files.
Check with `bun run check:types` in `packages/coding-agent`.

## Known failures on plain upstream

On v18.14.2, 26 tests in `test/task` and `test/eval` fail without any patch. Worktree tests fail because the commit
proxy blocks their git identity. The cell-syntax-error tests and some startup tests fail too. Compare against this
list before blaming a patch.
