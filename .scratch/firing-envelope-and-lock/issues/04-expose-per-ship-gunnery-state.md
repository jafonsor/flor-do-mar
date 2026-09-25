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

## Decisions recorded by the implementation

Status: implemented in the issue 04 commit. Every acceptance criterion above is met.

- **The envelope test is extracted, not copied.** `Domain.hs` gains `BroadsideGeometry` (holds / beyond range / outside arc) and `broadsideGeometry`, and `canFireBroadsideWith` takes its range and arc steps from it. Those two comparisons now exist once in the repository, so the per-side verdict the snapshot publishes and the condition the volley phase enforces are one computation. The guard order — finished scenario, attacker disabled, target disabled, reloading, range, arc — and every refusal value are unchanged, and issue 02's firing tests are untouched.
- **The published verdict is geometry plus a lock.** `lockedTargetShip` resolves a lock to a hull the scenario carries and refuses a self-lock. A ship with no lock, a lock on a ship the scenario does not carry, and a state built by hand with a self-lock all publish "no side holds the target" rather than an error or an accidental highlight.
- **The reload pair is `shipSnapshotReloadTicksRemaining` / `shipSnapshotReloadTicksTotal`.** The remaining field is renamed from `shipSnapshotReload` and its consumers are updated. A readout needs both numbers, and these two names cannot be swapped by accident.
- **The tuning travels as the `BroadsideTuning` record**, mirroring `shipSnapshotMovementPhysics`, and it is the record the volley phase validates against: the snapshot and the tick are both handed `broadsideTuningForShip`. `shipSnapshotReloadTicksTotal` projects that record, exactly as `shipSnapshotMaxSpeed` projects the movement physics.
- **`EngagementSnapshot`, `combatSnapshotEngagement`, `pointDistance` and `BattleScene`'s `battleSceneRange` are deleted**, with the hardcoded `PlayerShip`→`EnemyShip` checks. `battleSceneRange` was written and never read, so it is removed rather than re-sourced.
- **`BattleScene`'s markers carry the drawing inputs for issues 06 and 07** — tuning, locked target, permission, reload remaining and total, and both per-side verdicts — taken straight off the snapshot. The client does not recompute the verdict, so the highlight it draws and the condition the guns obey cannot disagree.
- **`Main.hs`'s engagement panel becomes a placeholder gunnery panel** reading only the snapshot: locked target, fire at will, reload remaining of total. It is deliberately not the gun panel, which issue 06 owns, and it derives no broadside verdict. `docs/agents/testing-and-tooling.md`'s description of the page's ground-truth text is updated to match.
- **No render node is added or changed.** The mesh count assertions in the render tests are untouched and still pass, because this issue changes the read model rather than the picture.
