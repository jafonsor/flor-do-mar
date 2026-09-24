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
- **The tick ordering is settled: a reload that reaches zero on a tick can fire on that same tick.** The reload decrements at the top of the tick, before the tick's commands are applied, so an arm order applied on the tick the reload completes is accepted — the guard reads the counter's post-decrement value — and catches that tick's volley. Commands and the volley phase share one tick, so from the player's side a volley leaves on the tick after they arm. Both boundary cases are written into test names: the tick the reload reaches zero fires, and arming on that tick is accepted.
- **Carry-forwards from the issue 01 review.** Issue 01 had to delete coverage that could only be reached by firing. This issue owns restoring it, in this commit:
  - an API-level terminal-state test (the deleted `testLocalApiReportsTerminalState`): fire through the local API until the duel ends, assert the winner, and assert that a finished scenario stops advancing;
  - the configured gunnery tuning travelling through the API (the deleted `testConfiguredLocalApiBroadsideTuning`): a tuned damage and reload from the config reach the snapshot;
  - `testConfiguredLocalApiHotReloadsLiveEngagement` had lost its proof that a **reloaded** config's broadside damage and reload ticks are what a volley actually uses, and its "hot reload keeps player reload" assertion had become vacuous (0 == 0). Both are restored, the reload one by firing before the hot reload so the counter is non-zero across it.
- **This issue supersedes exactly one issue 01 rule.** `testReloadCooldownIsUnaffectedByFiringStateCommands` asserted that `SetFireAtWill PlayerShip True` succeeds while `shipReload` is above zero ("fire at will does not need loaded guns"). Re-engaging during a reload is now refused and observable through `canSetFireAtWill`, so that assertion is deliberately changed to expect the refusal, and the test name and comment say the arm order was refused. The test's real subject is untouched: the reload counter is neither reset nor slowed by firing-state commands, and still counts to zero.
- **Decisions this issue made and pinned in tests.** The volley phase sits after the tick's commands and before its movement, so a volley's damage lands in the tick's snapshot (and `finishIfTerminal` still runs after it) and the envelope test uses the post-command, pre-movement geometry the client last drew. Volleys within one tick resolve simultaneously — every shot is computed against the state at the start of the phase, so neither ship can disable the other out of its own shot — which is what issue 05's enemy volleys will rely on.
- **The arc validation that makes the two sides disjoint is issue 03's.** Until it lands, `fireVolleys` takes the first side that reports `BroadsideReady`, port before starboard, so a config whose half-angle exceeds 90 degrees still fires exactly one broadside rather than two; with the shipped 45-degree arc there is exactly one candidate side.
