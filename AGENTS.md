## Agent skills

### Issue tracker

Issues and PRDs are tracked as local markdown files under `.scratch/`. See `docs/agents/issue-tracker.md`.

### Triage labels

This repo uses the default five-role triage vocabulary. See `docs/agents/triage-labels.md`.

### Domain docs

This repo uses a single-context domain documentation layout. See `docs/agents/domain.md`.

### Testing and local tooling

Movement tests and browser-driving traps that produce false signals. See `docs/agents/testing-and-tooling.md`.

### Git

Use `./scripts/git` for every git call, so the version in play is the nix-built one the dev shell supplies. A "tool not found" usually means the shell predates the current flake — see `docs/agents/git-workflow.md` before committing, switching branches, or rewriting history.

### Recording lessons

When work turns up something worth keeping, propose where it goes before writing it. See `docs/agents/recording-lessons.md`.

### Frontend checks

After frontend changes, run `nix develop --command cabal build flor-do-mar-client` to catch client compile errors before handoff.
