# Git In This Repo

Git usage guidelines for this repo.

## Use `./scripts/git`

```bash
./scripts/git status --short
./scripts/git log --oneline -5
```

Arguments pass through untouched. The harness refuses git reached the ordinary
way:

```
$ git --version                  → error: tool 'git' not found
$ /usr/bin/git --version         → error: tool 'git' not found
$ env git --version              → error: tool 'git' not found
$ nix develop --command git ...  → error: tool 'git' not found
$ /nix/store/…-git-2.55.0/bin/git --version → git version 2.55.0
```

The refusal follows the **resolved binary**, not the command word. `/usr/bin/git`
is the Apple/Xcode build, and that is the one git refused here; every nix-built git
in the store runs. Two tests prove it: inside a `nix develop` shell `command -v git`
prints `/usr/bin/git` while running it is still refused, and a renamed copy of git's
binary is refused or allowed according to which binary it execs.

`pkgs.git` in `flake.nix` would only change which binary PATH resolves to, and that
binary is still refused. Escalating does not help either: a `danger-full-access`
retry of `/usr/bin/git` fails the same way, because the harness decides before the
sandbox is consulted.

The wrapper pins `/nix/store/304vhl9qr5774qkv5rrqa0xbg429j2kk-git-2.55.0/bin/git`
and prints what to do if that path is collected. Override it for one command with
`FLOR_DO_MAR_GIT=/nix/store/…/bin/git ./scripts/git …`; `ls -d
/nix/store/*git-*/bin/git` lists the candidates. Confirm the wrapper works with
`./scripts/git rev-parse --is-inside-work-tree`.

## Never `reset --hard` on uncommitted work

`--hard` keeps the commits and discards the files, so it deletes work that exists
only in the working tree — even when the tree looks clean and every feature has a
commit. A green test run proves the *files* are right and says nothing about the
*commits*.

```bash
./scripts/git status --short          # a clean tree does NOT mean the work is committed
./scripts/git log --oneline -5        # check each file you care about is in a commit
```

Before any reset, checkout, or rebase:

- `cp` the files you are about to risk to `/tmp/`.
- Prefer `--soft` or `--mixed`. Both move only the branch pointer and the index,
  leaving the working tree alone.

## Check every commit

A staged set short by one path commits happily, and the commit does not say so.

```bash
./scripts/git diff --cached --name-only    # exactly the files you meant, no more, no fewer
./scripts/git commit -q -F - <<'EOF'
...
EOF
./scripts/git show --stat --format="" HEAD # what the commit actually contains
```

- `./scripts/git commit -a` after `./scripts/git reset --mixed <commit>` creates a
  **new** commit on top instead of folding into the existing one: two commits
  sharing a message, with the change still in the old one. To fold, stage the files
  and use `./scripts/git commit --amend`.
- `grep` over a one-line `--oneline` summary says nothing about file contents.
  Inspect a commit with `./scripts/git show <commit>:<path>`.

## Recovery: erased commits stay addressable

A reset moves a branch pointer; it does not delete the commits that were reachable,
so anything committed earlier stays addressable by hash while it is recent.

```bash
./scripts/git show <commit>:<path> > <path>   # restore one file from an erased commit
./scripts/git reflog                          # the pre-reset tip, if you lost the hashes
```

## Rewind a messy sequence

Rewrite by going back to before the mess, not by editing forward:

```bash
./scripts/git reset --soft <last good commit>   # pointer moves; index and files keep everything
./scripts/git reset                             # unstage all, so you can re-stage deliberately
```

Then re-commit one slice at a time, checking each. If only the *messages* are wrong
and the trees are right, `--amend` and `--soft` re-commits are enough.

## Repo specifics

- Identity is configured: `João Rodrigues <jrodrigues@imaginarycloud.com>`.
- Run `cabal` directly. The dev shell tools (`ghc`, `cabal`, `ghcid`, `nixfmt`,
  `playwright`, `node`) are already on PATH from `/nix/store`;
  `nix develop --command` only adds a nix evaluation that gets denied writing nix's
  fetcher cache outside the workspace.
- Build with `CABAL_DIR="$PWD/.cabal-local" cabal build all`. Cabal's default log
  path is outside the workspace and that write fails *after* a successful link, so
  the build looks broken when it is not.
- The frontend check is `cabal build flor-do-mar-client`. Without the dev shell on
  PATH, use the `nix develop --command` form from `AGENTS.md`.
- `main` takes fast-forward merges while the feature branch is unmerged. When `main`
  is an ancestor of the branch, `./scripts/git merge --ff-only <branch>` cannot
  conflict; check with `./scripts/git merge-base main HEAD` and `./scripts/git
  rev-parse main`.
- Pushing is the human's job unless asked.
