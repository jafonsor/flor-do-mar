Status: ready-for-agent

# Hot Reload Valid Config Into Live Engagement

## What to build

Enable dev-mode config hot reload for the local playtest workflow. The local client polls runtime config every 500ms. When parsing and validation both succeed, the active config store updates without restarting the app. Live ships remain linked to their boat kind, so valid edits to movement, combat, body size, and max hull apply to matching live boats while preserving live instance state such as damage taken, current speed, reload, position, current heading, and target heading. Reloading tick duration updates the client tick cadence.

## Acceptance criteria

- [ ] Local dev hot reload polls runtime config every 500ms.
- [ ] A valid config reload atomically replaces the active config used by the live engagement.
- [ ] Live ships keep their selected boat kind and resolve updated body, movement, and combat values from the new active config.
- [ ] Live instance state is not reset by valid config reloads.
- [ ] Max hull changes preserve damage taken and recalculate current hull from the new max hull, clamped at zero.
- [ ] Valid tick duration changes update the local client tick cadence without restarting the app.
- [ ] Hot reload continues while the setup overlay is open.

## Blocked by

- `.scratch/hot-reloadable-boat-physics/issues/01-load-configured-default-engagement.md`
- `.scratch/hot-reloadable-boat-physics/issues/03-run-configured-movement-physics.md`
- `.scratch/hot-reloadable-boat-physics/issues/04-use-boat-combat-tuning.md`

## Comments

