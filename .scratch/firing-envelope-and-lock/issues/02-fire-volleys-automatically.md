Status: ready-for-agent

# Fire Volleys Automatically From a Tick Phase

## What to build

Make guns fire themselves. This replaces `applyCommand`'s manual firing effect with a tick phase that resolves volleys from the state the previous issue introduced.

For each ship, on each tick: if the ship is permitted to fire, its guns are loaded, and its locked target lies inside one of its broadsides' firing envelopes, that broadside fires and the ship enters a reload.

The rules that make this a mechanic rather than a timer:

- **The side is not chosen.** Whichever broadside holds the target fires. The other does not. Because the two firing arcs are disjoint by construction, there is exactly one candidate side.
- **One reload covers both broadsides**, exactly as the shared counter works today. Firing either side loads both.
- **Disengaging during a reload cancels the volley that was coming.** If the reload counter reaches zero on a tick and permission was withdrawn before that volley left, no volley fires. Disengaging does not cancel or pause the reload itself.
- **Re-engaging during a reload is refused.** A ship whose reload counter is above zero cannot be granted permission. The refusal is observable by the caller.
- **Disengaging does not cost readiness.** The reload counter continues to zero while permission is absent, so a re-engaged ship is as ready as it would have been.
- **A volley needs a lock.** With no locked target, no volley fires regardless of permission.

The phase reuses the existing broadside check rather than introducing a second predicate, so the envelope the client draws and the envelope the simulation enforces stay the same computation.

## Acceptance criteria

- [ ] A volley fires on the next tick after permission is granted, when the locked target is inside a firing envelope and the guns are loaded.
- [ ] No volley fires when the locked target is outside both envelopes, when the guns are reloading, when permission is absent, or when no target is locked.
- [ ] The side that fires is the one whose envelope holds the target, and the other side does not fire.
- [ ] Firing either side starts the one shared reload, so the other side cannot fire until it completes.
- [ ] Withdrawing permission during a reload prevents the volley that would otherwise leave when the reload completes.
- [ ] Withdrawing permission does not stop the reload counter from reaching zero.
- [ ] Granting permission while the reload counter is above zero is refused and observable by the caller.
- [ ] Granting permission after the reload reaches zero succeeds and the next tick can fire.
- [ ] A volley does not fire without a locked target, even with permission granted and guns loaded.
- [ ] A disabled ship fires nothing.
- [ ] Volleys apply the configured damage and use the configured reload, range, and arc values per boat.
- [ ] Tests cover each rule above through the pure tick transition and the local combat API.

## Blocked by

- `.scratch/firing-envelope-and-lock/issues/01-model-locked-targets-and-fire-permission.md`

## Notes for whoever implements it

- The existing firing tests were written against `FireBroadside` and a manual side choice. They are the specification for what the new tests must cover, not something to preserve verbatim: rewrites should assert *why* a volley did or did not leave, not that a command was accepted.
- The tick ordering matters and should be asserted deliberately. Reload decrements happen at the top of the tick today, before commands are applied. Decide and test whether a volley that empties the reload in a given tick can fire in that same tick, and write the answer down in the test names.
