Status: ready-for-agent

# Expose Per-Ship Gunnery State in the Snapshot

## What to build

The client needs to draw a firing envelope and a reload readout, and it must draw them from the same values the simulation enforces rather than from a second source that can drift. Today the snapshot carries the reload counter but not the total, and neither the range nor the arc angle reaches the client at all; the range and angle only exist in the loaded config, which is not passed into the battle view.

Put the gunnery tuning on `ShipSnapshot`, mirroring how `shipSnapshotMovementPhysics` already travels with each ship. Then replace the player-versus-enemy engagement read model with per-ship firing state.

`EngagementSnapshot` is hardcoded to `PlayerShip` against `EnemyShip` and exposes exactly two broadside checks, one per side. That shape cannot express a locked target, a permission flag, or the possibility of more than one enemy, and it is the reason the client currently has no way to know what its own guns are pointed at. It goes away, replaced by fields on each ship's snapshot.

The per-side verdict the client draws from — which broadside, if any, currently holds the locked target — should be part of the snapshot rather than recomputed in the client, so the drawn highlight and the enforced firing condition cannot disagree.

## Acceptance criteria

- [ ] `ShipSnapshot` exposes the ship's broadside tuning: practical range, firing arc degrees, and total reload ticks.
- [ ] `ShipSnapshot` exposes the ship's locked target, its fire permission, and the reload ticks remaining alongside the total.
- [ ] `ShipSnapshot` exposes, per side, whether that broadside currently holds the locked target.
- [ ] The hardcoded player-versus-enemy engagement checks are removed from the read model.
- [ ] Snapshot tests assert each new field, including that a locked ship reports its target and an unlocked ship reports none.
- [ ] A test asserts the exposed tuning matches the boat config the ship is flying, so a config hot reload is reflected in the snapshot.
- [ ] `BattleScene`'s view model carries what the envelope and reticle drawing will need, including the per-side target-in-reach state.

## Blocked by

- `.scratch/firing-envelope-and-lock/issues/01-model-locked-targets-and-fire-permission.md`
- `.scratch/firing-envelope-and-lock/issues/03-reduce-range-and-fit-engagement-on-screen.md`

## Notes for whoever implements it

- `shipSnapshotMovementPhysics` is the precedent to follow: per-ship tuning riding inside the snapshot, rather than the client joining a config dynamic by boat kind. The join approach was considered and rejected because the config hot reloads during a live battle, which is exactly when a drawn envelope and an enforced envelope would drift apart.
- `shipSnapshotName` and `shipSnapshotDisplayName` are currently both set to the same value. Do not copy that pattern into the new fields.
- Widening `ShipSnapshot` touches the snapshot-to-state round trip used by the tests, which reconstructs domain state from a snapshot. Keep that round trip honest rather than dropping the new fields on the way back.
