Status: ready-for-agent

# Model Locked Targets and Fire Permission

## What to build

Give a ship the two pieces of firing state the new model needs, and the commands that set them.

A ship holds at most one **locked target** and a **fire permission** flag. Both are live ship state, alongside reload and damage — they are not boat configuration and must not be affected by a config hot reload. Both sides start with no lock and no permission.

Two commands replace `FireBroadside`, which is deleted in this change:

- a lock command carrying a target ship id, which locks that target or unlocks it if it is already locked
- a fire permission command carrying a ship id and a boolean

Locking is a fire-control solution, so it is validated in the domain, not only in the input layer. A ship may not lock itself, and may not lock a ship that is not in the scenario. This guard belongs in the same guard chain as the existing broadside checks, because the current chain has no self-target check at all and geometry blocks self-damage only by accident of the arc maths.

Locking and permission are independent of each other and of reload. Setting either does not start, cancel, or otherwise touch a reload, and does not require the guns to be loaded.

This issue models state. It does not fire anything — the volley that consumes this state is the next issue.

## Acceptance criteria

- [ ] A ship's state includes a locked target, which is either absent or one ship id, and a boolean fire permission.
- [ ] Both ships start with no locked target and no fire permission.
- [ ] The lock command locks the named target, and the same command against the already-locked target unlocks it.
- [ ] A lock command naming the ship itself is refused and leaves the lock state unchanged.
- [ ] A lock command naming a ship that is not in the scenario is refused and leaves the lock state unchanged.
- [ ] The fire permission command sets permission true or false, and is independent of lock state.
- [ ] Neither command changes the reload counter, and neither requires the guns to be loaded.
- [ ] Both commands are carried in the snapshot read model so the client can observe them.
- [ ] Hot reload of boat config does not reset either field on a live ship.
- [ ] A refused lock is observable by the caller rather than silently ignored.
- [ ] `FireBroadside` and its side argument are no longer part of the command type.

## Blocked by

None. This is the first issue.

## Notes for whoever implements it

- Removing `FireBroadside` breaks the client's fire buttons and several existing tests. That is expected: the client's gun panel arrives in a later issue, and the existing firing tests are rewritten by the automatic-fire issue. Update the tests that will not compile rather than leaving the tree broken.
- **Nothing can fire between this issue and issue 06, and that is intended.** Deleting `FireBroadside` takes the client's "Fire port" and "Fire starboard" buttons out of the tree, and the gun panel that replaces them only arrives in issue 06; issues 02 to 05 are domain, config, snapshot and AI work. Do not add a bridging control to keep firing alive in the meantime, and do not weaken this issue to avoid the gap. "Leaves the tree building and the suite passing" means exactly that, not "playable".
- The two commands are `Lock shipId targetId`, which locks that target or releases it when it is already locked, and `SetFireAtWill shipId permitted`. Both names come from the Targeting and Gunnery glossary in `CONTEXT.md`, and later issues and the client use them unchanged.
- The scope is deliberately quiet. Nothing fires at the end of this issue, which means the existing reload tests are the ones that prove the new state does not disturb the cooldown.
