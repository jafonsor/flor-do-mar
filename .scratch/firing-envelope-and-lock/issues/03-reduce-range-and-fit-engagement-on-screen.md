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
- [ ] A test asserts the camera's zoom and centre, and a config test asserts the new validation bound.
- [ ] The enemy's orbit ring is fully inside the visible world extent for a whole circuit.

## Blocked by

- `.scratch/firing-envelope-and-lock/issues/02-fire-volleys-automatically.md` — the range change must not be tuned against a firing path that is still manual, and the arc validation tightening depends on there being exactly one candidate side per volley.

## Notes for whoever implements it

- These three values are entangled and were chosen together: the range determines what the camera must fit, and the zoom determines how large the hulls read. Changing one later means re-checking the other two against the criteria above.
- The reduced range means the duel's starting separation of 80 units is **outside** both ships' reach, so the fight opens with a closing phase. That is intended, and it is the first thing to confirm on screen.
- **Do this before the visibility work.** Whether a 96-unit envelope and a 16-unit hull are legible together at 0.6 is the riskiest assumption in the whole feature, and it is worth ten minutes of looking before any wedge geometry is written.
