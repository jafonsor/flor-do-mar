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
