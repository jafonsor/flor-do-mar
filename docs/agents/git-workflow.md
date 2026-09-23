# Git In This Repo

Git usage guidelines for this repo.

## Use `./scripts/git`

```bash
./scripts/git status --short
./scripts/git log --oneline -5
```

Arguments pass through untouched, so use it exactly as you would git. A bare `git`
does not run here, so call the wrapper every time.

It pins `/nix/store/304vhl9qr5774qkv5rrqa0xbg429j2kk-git-2.55.0/bin/git` and says
what to do if that path is collected. Check it with `./scripts/git rev-parse
--is-inside-work-tree`; override it for one command with
`FLOR_DO_MAR_GIT=/nix/store/…/bin/git ./scripts/git …`, and find candidates with
`ls -d /nix/store/*git-*/bin/git`.

## Never `reset --hard` on uncommitted work

`--hard` discards the working-tree files, so it destroys work that is not in a
commit yet — even when the tree looks clean and every feature has one. A green test
run proves the *files* are right, never the *commits*: check before you trust it.

```bash
./scripts/git status --short          # clean tree does NOT mean the work is committed
./scripts/git log --oneline -5        # check each file you care about is in a commit
```

Before any reset, checkout, or rebase: `cp` the files you are about to risk to
`/tmp/`, and prefer `--soft` or `--mixed`, which move only the branch pointer and
the index.

## Check every commit

A staged set short by one path commits happily, and the commit does not say so.

```bash
./scripts/git diff --cached --name-only    # exactly the files you meant, no more, no fewer
./scripts/git commit -q -F - <<'EOF'
...
EOF
./scripts/git show --stat --format="" HEAD # what the commit actually contains
```

- To fold a change into an existing commit, stage the files and use
  `./scripts/git commit --amend`. After `./scripts/git reset --mixed <commit>`,
  `commit -a` creates a **new** commit on top instead: two commits sharing a
  message, with the change still in the old one.
- `--oneline` and `grep` say nothing about file contents. Read a commit with
  `./scripts/git show <commit>:<path>`.

## Recovery: erased commits stay addressable

A reset moves a branch pointer without deleting the commits that were reachable,
so anything committed earlier stays addressable by hash while it is recent.

```bash
./scripts/git show <commit>:<path> > <path>   # restore one file from an erased commit
./scripts/git reflog                          # the pre-reset tip, if you lost the hashes
```

## Rewind a messy sequence

Rewind to before the mess instead of editing forward:

```bash
./scripts/git reset --soft <last good commit>   # pointer moves; index and files keep everything
./scripts/git reset                             # unstage all, so you can re-stage deliberately
```

Then re-commit one slice at a time, checking each. If only the *messages* are wrong
and the trees are right, `--amend` alone is enough.

## Repo specifics

- Identity is configured: `João Rodrigues <jrodrigues@imaginarycloud.com>`.
- Run `cabal` directly. The dev shell tools are already on PATH; `nix develop
  --command` only adds a nix evaluation that gets denied writing nix's fetcher cache
  outside the workspace.
- Build with `CABAL_DIR="$PWD/.cabal-local" cabal build all`. Cabal's default log
  path is outside the workspace and that write fails *after* a successful link, so
  the build looks broken when it is not.
- The frontend check is `cabal build flor-do-mar-client`. Without the dev shell on
  PATH, use the `nix develop --command` form from `AGENTS.md`.
- `main` takes fast-forward merges while the feature branch is unmerged. If `main`
  is an ancestor, `./scripts/git merge --ff-only <branch>` cannot conflict; if it is
  not, that command refuses (exit 128) and changes nothing, so it is safe to try.
  To check first: `./scripts/git merge-base main HEAD`.
- Pushing is the human's job unless asked.
