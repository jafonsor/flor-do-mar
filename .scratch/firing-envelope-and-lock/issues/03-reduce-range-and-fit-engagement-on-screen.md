Status: ready-for-agent

# Reduce Gun Range and Fit the Engagement On Screen

## What to build

Three coupled values, all of which exist to make the firing envelope visible and legible. Nothing here fires; these are the numbers the drawn area and the enforced area both derive from.

- **Practical range becomes 48 world units**, down from 100, in both boat configs. That is three lengths of the big ship. The intent is legibility and pacing, not realism — real cannon range was far longer than this, so the historical argument points the other way and must not be used later to justify raising it again.
- **Camera zoom becomes 0.6**, so an engagement with both ships at the duel's starting separation fits on the canvas. At 0.6 the drawn range spans roughly 96 world units per ship, the starting separation is 80, and the big boat still renders around 46 by 17 pixels.
- **The enemy's orbit centre moves from `(0, 80)` to `(0, 40)`**, the point the camera is already centred on. Today the orbit ring straddles the top edge of the canvas and the enemy spends half its circuit off screen. There are **two** construction sites to change, not one.

The engine's angular coverage stays disjoint, so the firing arc validation tightens at the same time. The shipped half-angle of 45 is unaffected; the change only rejects configurations that would make the two broadsides overlap into one all-round battery.

## Acceptance criteria

- [ ] `broadside_range` is 48 in both shipped boat configs.
- [ ] Firing arc validation rejects a half-angle above 90 degrees with a diagnostic naming the field, and still accepts the shipped 45.
- [ ] The battle camera's zoom is 0.6 and its centre remains the arena centre.
- [ ] Both places that build the enemy orbit autopilot use `(0, 40)` rather than `(0, 80)`.
- [ ] At the duel's starting separation, both ships and the whole of both ships' range reach are inside the visible world extent.
      **Clarified by the implementation: both ships, each ship's engagement-facing envelope and the contested space are inside; each ship's outward-facing wedge is not, by 13 world units.** See the decisions recorded below.
- [ ] A test asserts the camera's zoom and centre, and a config test asserts the new validation bound.
- [ ] The enemy's orbit ring is fully inside the visible world extent for a whole circuit.

## Blocked by

- `.scratch/firing-envelope-and-lock/issues/02-fire-volleys-automatically.md` — the range change must not be tuned against a firing path that is still manual, and the arc validation tightening depends on there being exactly one candidate side per volley.

## Notes for whoever implements it

- These three values are entangled and were chosen together: the range determines what the camera must fit, and the zoom determines how large the hulls read. Changing one later means re-checking the other two against the criteria above.
- The reduced range means the duel's starting separation of 80 units is **outside** both ships' reach, so the fight opens with a closing phase. That is intended. It is pinned by `testShippedDuelOpensOutsideBothShipsReach`, and the on-screen confirmation moves to issue 07 (see below).
- Whether a 96-unit envelope and a 16-unit hull are legible together at 0.6 is the riskiest assumption in the whole feature. Issue 03 checked it **numerically** rather than by eye, because driving a browser for it needs an escalation out of the workspace-only sandbox and the firing envelope that would make the picture informative does not exist until issue 07. The numbers are recorded below; the look moves to issue 07, which is the first issue with a wedge to look at.

## Decisions recorded by the implementation

Status: implemented in the issue 03 commit. Every acceptance criterion above is met, except that the extent one is met only in the clarified form recorded below.

- **The legacy domain tuning stays where it is, and the divergence is real.** `broadsideRange` / `legacyBroadsideTuning` in `Domain.hs` and the `caravelaDuel` fixture still carry the old 100-unit reach. That is the pre-config path: `newLocalCombatApi` is used by tests only, while the client always builds `newConfiguredLocalCombatApi`, so the shipped numbers are the two TOMLs. Every claim this issue makes about shipped numbers is asserted against `configuredDefaultEngagement` / `loadRuntimeCombatConfig`, never against `caravelaDuel`. The repo already accepts this kind of divergence — `caravelaMovement` (turn_rate 360) against the shipped config (turn_rate 30) — and `docs/agents/testing-and-tooling.md` records the lesson to add shipped-config coverage rather than to align the fixture. `broadsideRange` now says so in a comment.
  Two API-level tests had assumed the shipped reach crossed the opening separation and now supply their own reach through `configReachingAcrossTheOpening` (90 units, the opening separation plus margin): `testConfiguredLocalApiBroadsideTuning` and `testConfiguredLocalApiHotReloadsLiveEngagement`. Both are about a tuning path rather than about the shipped geometry, and the shipped opening is pinned by its own test.
- **The extent criterion is not satisfiable as written; it is clarified, not reinterpreted.** At zoom 0.6 with viewport 160 by 90 centred on `(0, 40)` the visible world is x ∈ [-133.3, 133.3], y ∈ [-35, 115]. At the opening geometry the *engagement-facing* envelopes and the contested space fit: the player's port wedge reaches y = 48, the enemy's south wedge y = 32, and both stay within x = ±33.9. Each ship's *outward-facing* wedge reaches 13 units past the canvas edge — the player's starboard envelope to y = -48 against the -35 floor, the enemy's north envelope to y = 128 against the 115 ceiling. `testShippedEngagementFitsTheVisibleExtent` asserts what is true (both hulls, both engagement-facing envelopes and the contested space inside the extent) and pins the two outward numbers as recorded facts, so a later camera or range change cannot move them unnoticed. Fitting the outward wedges as well would need the visible world to span y ∈ [-48, 128], a zoom of about 0.51, which would render the big boat at roughly 39 by 15 pixels instead of 46 by 17 — a legibility cost this issue did not take.
- **Legibility is verified numerically, not in a browser.** The battle canvas's drawing buffer is 760 by 428 and the camera's world viewport is 160 by 90, so at 0.6 one world unit is 2.85 pixels: the big boat renders 45.6 by 17.1 pixels and the small boat 25.65 by 8.55, the smallest dimension rounding to nine pixels. `testShippedZoomRendersHullsLegibly` asserts those numbers, and it is the reason the zoom did not go lower to fit the outward wedges above. The visual check on screen is deferred to issue 07.
- **The arc bound is inclusive at 90 degrees.** `validateBoat` rejects a half-angle above 90 with a diagnostic naming `firing_arc_degrees`, and the fixtures pin both sides of the boundary: `test/fixtures/config-arc-too-wide` (120, rejected) and `test/fixtures/config-arc-at-limit` (90, accepted), each a copy of the shipped assets with only that field changed so the `id` still matches its TOML basename. The shipped 45 is asserted against `config/combat` by `testLoadsRuntimeCombatConfig`.
- **Two test changes are deliberate rather than incidental.** `testInitialBattleRenderScene`'s zoom assertion becomes exactly 0.6 rather than being loosened. `testEnemyOrbitAutopilotIssuesNavigationOrders` now asserts the first orbit centre is the arena centre `(0, 40)` and measures the fixed radius from it, while separately asserting the enemy still starts at `(0, 80)`. The tests that convert screen coordinates (`testBattleInputHoverIntent`, `testBattleInputMouseNavigationGesture`) use the canvas centre, which is zoom-invariant, so they are unchanged and still pass; nothing else assumed zoom 1, since `camera2DMatrix` and `screenToBattlePoint` are the only consumers of `cameraZoom` and both divide by it.
- **One stale harness claim was corrected in the same change.** `test/DiagnosisDivergence.hs` measured the enemy's distance from `(0, 80)` while printing "distance from orbit centre". That point is the enemy's starting position, not the orbit centre, so it now reads the centre from the autopilot it is measuring. The check is unchanged in the pass it requires; it measures 24.20 against a radius of 24.
