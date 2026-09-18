Status: ready-for-agent

# Keep Last Valid Config On Invalid Reload

## What to build

Make invalid hot reloads safe for live tuning. If a config edit is missing, malformed, or semantically invalid during hot reload, the local client prints detailed diagnostics to the server console and keeps the last valid active config and current engagement state intact. Parser diagnostics include filename plus line and column when available. Semantic diagnostics include a field path, explanation, and practical fix hint where possible.

## Acceptance criteria

- [ ] Invalid hot reloads do not replace the last valid active config.
- [ ] Invalid hot reloads do not mutate active combat state.
- [ ] Missing or deleted config files during hot reload keep the engagement running with the last valid config.
- [ ] Parser diagnostics include filename plus line and column when the parser provides them.
- [ ] Semantic diagnostics include field path, plain-English explanation, and a useful fix hint where practical.
- [ ] Startup invalid config still fails fast rather than using last-valid behavior.

## Blocked by

- `.scratch/hot-reloadable-boat-physics/issues/05-hot-reload-valid-config-into-live-engagement.md`

## Comments

