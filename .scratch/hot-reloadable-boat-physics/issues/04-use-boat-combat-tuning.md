Status: ready-for-agent

# Use Boat Combat Tuning

## What to build

Move broadside combat tuning onto boat configuration while preserving the command-based combat model. Broadside range, damage, reload cooldown, and firing arc come from the firing boat's current boat kind config. The simulation continues to apply broadside commands on ticks and exposes reload state through snapshots.

## Acceptance criteria

- [ ] Broadside range is resolved from the firing boat kind config.
- [ ] Broadside damage is resolved from the firing boat kind config.
- [ ] Reload cooldown is resolved from the firing boat kind config.
- [ ] Firing arc degrees are resolved from the firing boat kind config.
- [ ] Broadside hit checks use current physical heading and configured firing arc.
- [ ] Existing broadside command flow and snapshot reload state continue to work through the Combat API.

## Blocked by

- `.scratch/hot-reloadable-boat-physics/issues/01-load-configured-default-engagement.md`

## Comments

