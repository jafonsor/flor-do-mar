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

The harness blocks `git` by name, and `reset --hard` destroys work that exists only in the working tree. See `docs/agents/git-workflow.md` before committing, switching branches, or rewriting history.

### Frontend checks

After frontend changes, run `nix develop --command cabal build flor-do-mar-client` to catch client compile errors before handoff.
