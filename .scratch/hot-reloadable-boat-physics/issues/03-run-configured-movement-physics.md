Status: ready-for-agent

# Run Configured Movement Physics

## What to build

Run the first pass of configured ship movement physics through the existing fixed-tick combat simulation. Heading commands set target heading rather than snapping the physical heading. Sail commands set target speed from the configured sail state. On each tick, current heading turns toward target heading, current speed accelerates or decelerates toward target speed, and position advances from current physical heading and current speed using the configured tick duration. Snapshots and UI expose enough movement state for the tactical battle view to show physical orientation and helm intent.

## Acceptance criteria

- [ ] `SetHeading` updates target heading while current heading changes gradually over subsequent ticks.
- [ ] Effective turn rate uses configured turn rate, tick seconds, current movement state, and minimum turn speed factor.
- [ ] Sail state targets are configured: Sails Furled targets zero, Battle Sails targets battle speed, and Full Sails targets max speed.
- [ ] Current speed accelerates or decelerates toward the target speed using per-second configured values and tick seconds.
- [ ] Position advances from current heading and current speed over tick seconds.
- [ ] Firing arc checks continue to use current physical heading rather than target heading.
- [ ] Snapshots expose current speed, current heading, and target heading.
- [ ] The tactical battle view shows current heading and target heading markers.
- [ ] Wind remains structurally present and defaults to zero.

## Blocked by

- `.scratch/hot-reloadable-boat-physics/issues/01-load-configured-default-engagement.md`

## Comments

