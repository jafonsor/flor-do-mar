Status: ready-for-agent

# Draw the Firing Envelope

## What to build

Draw each broadside's reachable area on the canvas, so the player can steer by it.

The envelope is a sector: the firing arc swept out to the guns' practical range, with a circular outer edge. The renderer has no sector and no arbitrary polygon — a mesh is only ever a unit cube, a stroke path is a constant-width ribbon, and the ring primitive draws full circles only, with the angle hardcoded from zero. A partial arc therefore has to be built from a **stroke path fed sampled arc points**, and a helper that samples a sector's boundary is the new piece of geometry. Either extend the ring geometry with start and end angles or add a sector-outline sampler beside it; both are legitimate, but the sampling is the part that must be shared rather than duplicated per call site.

**A wedge is drawn only for a ship that has a locked target, and both of that ship's broadsides are drawn at once.** An unlocked ship shows no envelope. This applies to the enemy too: its envelopes appear once it has locked the player, which is the tell that the player has been targeted and is what makes the threat avoidable.

**Wedge rotation follows the hull heading**, and its size comes from the range and arc angles exposed in the snapshot — the same values the simulation enforces, so the drawn area cannot lie about the real one.

Two independent channels on the same shape, which must not be conflated:

- **Fill** shows reload progress, the same progress the reload circle shows, on both wedges because the reload is shared.
- **Highlight** shows that the locked target is currently inside that wedge. A wedge can be full and unhighlighted (loaded, but the target has turned away), or part-filled and highlighted (target in reach, still reloading).

Colours use the existing hull palette so the mapping is already learned: the player's wedge in the player's blue, the enemy's in the enemy's red, one shared highlight colour for whichever wedge holds the target, and a desaturated treatment while permission to fire is withdrawn. The player's own envelope and the enemy's must not look alike, because steering out of one and shooting with the other are the two halves of the mechanic.

Each ship's wedge nodes need names unique per ship and side: the renderer's geometry upload cache is keyed by primitive name, so duplicate names collide and a node reused for different geometry comparison-unequal to the wrong thing is a real failure mode the existing naming scheme avoids with a per-ship suffix.

Wedges must sit **above** the hull in z. Ships occupy a z range that spans the current overlay heights, so a wedge drawn at an existing overlay height around a ship it is anchored to would be buried inside that ship's hull.

## Acceptance criteria

- [ ] A locked ship renders two wedge nodes, one per broadside; an unlocked ship renders none.
- [ ] The enemy's wedges appear once it has locked the player.
- [ ] Wedge geometry matches the ship's heading, its snapshot range, and its snapshot arc angle.
- [ ] The wedge fill tracks reload progress, and both of a ship's wedges show the same fill because the reload is shared.
- [ ] The highlight appears on whichever wedge currently holds the locked target, and only on that one when only one does.
- [ ] Fill and highlight are independent: a full unhighlighted wedge and a part-filled highlighted wedge are both produced by the tests.
- [ ] The wedge is desaturated while the ship's fire permission is absent, independently of fill and highlight.
- [ ] The player's wedge and the enemy's wedge use different base colours.
- [ ] Wedge primitive names are unique per ship and per side.
- [ ] Wedges render above the hull in z.
- [ ] The camera's zoom change and the envelope drawing are verified together: at the shipped range, a whole envelope is visible for the player at the duel's starting position.

## Blocked by

- `.scratch/firing-envelope-and-lock/issues/04-expose-per-ship-gunnery-state.md`
- `.scratch/firing-envelope-and-lock/issues/06-gun-panel-and-click-to-lock.md`

## Notes for whoever implements it

- **The wedge will step, not slide.** Reload advances once per tick, so the fill has a small number of discrete states while the reload circle animates smoothly beside it. This was accepted deliberately: the circle is what the player times their order against, and the wedge answers "where can I shoot". If the stepping turns out to look broken next to the smooth circle, the fix is a per-frame animation clock — an architectural change that deserves its own decision, not a rider on this issue.
- **The existing render tests will need updating rather than working around.** They assert an exact mesh count for the initial scene and match on the ring and stroke constructors, and the scene node count changes here. Update them deliberately; do not loosen an exact assertion into a vague one to make the change fit.
- The existing overlay heights are all inside the hull's z range, which has not mattered because those overlays sit far from hulls. The wedge is the first overlay anchored to a hull, so it is the first to hit this.
