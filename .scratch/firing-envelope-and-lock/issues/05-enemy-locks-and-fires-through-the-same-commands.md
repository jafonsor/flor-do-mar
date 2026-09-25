Status: ready-for-agent

# Enemy Locks and Fires Through the Same Commands

## What to build

Make the enemy fight. It locks the player, orders fire at will, and keeps orbiting its centre.

The point of this issue is not the behaviour — the behaviour is deliberately minimal — but that the enemy **goes through the same commands a player uses**. The existing Autopilot rule in `CONTEXT.md` says a non-player behaviour issues orders through the same model available to player commands, avoiding special enemy paths, and this is the gunnery extension of that promise. If the enemy gets its own firing path, then the symmetric-lag property the whole design rests on disappears silently, and a bug in the player's firing is a bug the enemy does not share.

The enemy therefore cannot lock itself, cannot lock a ship that is not in the scenario, cannot be granted permission during a reload, and cannot fire without a lock — all for the same reasons the player cannot, because it is running the same code.

It locks **after a short delay from scenario start**, not on the first tick. Scenarios can be constructed with the lock already in place if that is simpler, but the AI must not acquire on tick 0.

It never disengages.

## Acceptance criteria

- [ ] The enemy acquires a lock on the player through the ordinary lock command, not by writing ship state directly.
- [ ] The enemy grants itself fire permission through the ordinary permission command, after its reload allows it.
- [ ] The delay before the enemy's first lock is a named, single-place constant rather than an inline literal, and is not zero.
- [ ] The enemy fires volleys through the same tick phase and the same envelope check the player uses.
- [ ] The enemy never withdraws permission.
- [ ] The enemy keeps orbiting its centre, unchanged by the targeting work.
- [ ] Tests assert the enemy's volleys obey the same rules: no volley without a lock, no volley outside the envelope, no volley during reload.
- [ ] A test asserts the enemy's permission is refused while its reload is above zero, proving it is subject to the same guard as the player.

## Blocked by

- `.scratch/firing-envelope-and-lock/issues/02-fire-volleys-automatically.md`
- `.scratch/firing-envelope-and-lock/issues/03-reduce-range-and-fit-engagement-on-screen.md`

## Notes for whoever implements it

- Do not give the autopilot a direct state-mutation shortcut even where it would be simpler. The value of this issue is the shared path.
- The enemy starts disengaged, like the player. Any opening exchange asymmetry should come from the lock delay and nothing else, and the delay should be tuned by playing rather than by reasoning.
- The duel's starting separation is outside the new gun range, so the enemy spends the opening of the fight closing distance with its guns silent. Confirm that reads as intended rather than as the enemy being broken.

## Decisions recorded by the implementation

Status: implemented in the issue 05 commit. Every acceptance criterion above is met.

- **The lock delay is `enemyLockDelayTicks = 3`**, in `FlorDoMar.Combat.Domain` beside the orbit constants and exported so a test can pin it. `combatTick` is incremented at the top of the tick before any command is applied, so the constant is compared against the counter's post-increment value: the enemy is unlocked on ticks 1 and 2 and locks on tick 3. **Three is a starting value chosen for feel, not a tuned one, and no play-test has confirmed it.** Tuning it is issue 07's, where the fight can be watched on screen; this is the one number in the issue that is a matter of how the opening reads rather than of what the rules are.
- **The orders are a pure list applied through `applyCommand`.** `enemyGunneryOrders` returns `[]`, `[Lock EnemyShip PlayerShip]` or `[SetFireAtWill EnemyShip True]`, and `issueEnemyGunneryOrders` folds them through the same `applyCommand` the tick folds the player's commands through. Nothing in the AI writes `shipLockedTarget` or `shipFirePermission`; `shipLockedTarget` is only read, and only to decide whether a lock is already held, since the `Lock` command toggles and re-issuing it would release the target.
- **The tick applies them after the player's queued commands and before the volley phase.** That is what makes the tick that arms the enemy a tick it can fire on, the same rule the player gets. A refused order leaves the state alone, so an arm refused during a reload is re-issued on the next tick rather than dropped — the refusal is observable for the enemy because it is the same `canSetFireAtWill` guard the player meets.
- **The test path reads the enemy's fight off the local API.** `testLocalApiEnemyClosesLocksArmsAndDamagesThePlayer` runs the shipped duel with the player stopped and holding its fire; the enemy closes, and the snapshot shows its lock, its permission, its reload and the player's hull falling by the boat's damage each time the shared reload completes. The player holding fire is deliberate: a player who shoots back disables an 80-hull boat before it fires twice, which is balance rather than mechanism.
- **The enemy cannot close on a fleeing player, and that is a balance observation for issue 07.** Both boats make 4 units a tick and the enemy circles a 24-unit ring, so against a player who keeps sailing the closest approach observed over 40 ticks of the shipped duel is 55 units — outside the 48-unit reach, so an opening exchange only happens if the player stops. The PRD's "the enemy spends the opening of the fight closing distance" holds; that the closing succeeds only against a player who stops does not, and it is recorded here rather than fixed, because range-keeping and positioning for the enemy are out of scope.
- **One issue 02 assertion is deliberately revised.** `testLocalApiReportsTerminalState` asserted the enemy never fires because it held no lock. It holds one now, so the test asserts the lock, the permission and the player's untouched hull for the reason that actually holds: the fixture furls the enemy's sails to pin it, and a pinned enemy ends up bow-on to the bearing — about 76.5 units away at roughly 90 degrees off both beams, so neither broadside bears, which the test pins as both `shipSnapshotPortHoldsTarget` and `shipSnapshotStarboardHoldsTarget` being false. The refusal is the **arc, not the range**: `startLocalDuel` flies the legacy scenario, whose `legacyBroadsideTuning` reach is 100, so 76.5 units is comfortably inside it. The test's real subject — the API reports the winner and a finished scenario stops advancing — is untouched.
