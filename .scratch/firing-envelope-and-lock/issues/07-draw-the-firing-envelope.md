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

## Decisions recorded by the implementation

Status: implemented in the issue 07 commit. Every acceptance criterion above is met.

- **The sector sampler is the shared piece, and it sits beside the ring.** `WebGL/Geometry.hs` gains `sectorArcPoints`, `sectorOutlinePoints`, `sectorFillGeometry` and `sectorWedgeGeometry`, over a `Sector` (radius, start and end angles, segment count) and a `SectorWedge` (that sector, the radius the reload has filled, the outline's width). `sectorArcPoints` is the only place a sector boundary is sampled: the outline asks it for the arc at the envelope's full radius, the fill asks it for the same arc at the radius the reload has reached, and `sectorWedgeGeometry` joins the two into one `Geometry3D` (a triangle fan plus a closed stroke path, indices offset past the fan's vertices). Extending `ringStrokeGeometry` with start and end angles was the other option; the sampler was chosen because the fill is not a stroke at all, so an arc-stroke extension would have left the fill sampling its own boundary or fanning a stroke's ribbon. `ringStrokeGeometry` is untouched and still draws full circles only.
- **One new node per side, not one per channel.** `Render/Scene.hs`'s `GeometryRef` gains `FiringEnvelopeGeometry SectorWedge`, and `geometryFor` generates it. A wedge is therefore a `RenderMeshNode`: one primitive per side carrying the fill, the always-full outline and the colour, which is what makes "two wedge nodes for a locked ship, one per broadside" true literally and what keeps the name unique per ship and per side. The wire format is unchanged — `DrawBatch` already encodes any `Geometry3D` as positions plus `Word16` indices and the browser replays it with `gl.TRIANGLES` — so ADR-0007's two-halves pairing is not touched. The geometry is described in the hull's own frame and the node's transform applies the heading, so turning does not re-upload a wedge; only the fill's radius changing does, once per tick of a reload, and the name-keyed cache is what makes that a re-upload rather than a collision.
- **The fill is the reload's radius, read through the panel's own function.** `sectorWedgeFilledRadius` is `range * reloadProgress remaining total`, importing `reloadProgress` from `GunPanel` — the same call the reload circle's fill is built from — so the wedge and the circle cannot read one reload differently. Empty at the volley that started the reload, full when the guns are loaded, and identical on both of a ship's wedges because the pair it reads is the shared one. The wedge steps per tick; no clock was added.
- **The angular convention is the domain's, in the hull's frame.** Port is the heading plus 90 degrees and starboard the heading minus 90, each spanning the half-angle either side, and the node's transform turns the frame onto the heading. `testFiringEnvelopeMatchesTheEnforcedEnvelope` proves the drawn area and the enforced one are the same area: it reads the wedge's own geometry out of the scene, puts it through the node's matrix, and asks the domain's `broadsideGeometry` about target positions on that drawn arc — every direction inside the drawn arc holds, directions just past either end are outside the arc, and the drawn reach's own direction past its end is beyond range. The extremes are compared to the beam the domain's own `broadsideHeading` gives, plus and minus the snapshot's half-angle, within the stroke's half width, which is under half a degree at the shipped radius. Swapping the port and starboard beams fails that test.
- **Colour is the highlight and the permission; the fill is the radius.** The base is the ship's own hull colour (`baseShipColor`: player blue, enemy red); a side that holds the target wears one shared highlight, `color 1 0.93 0.35 1`; and a ship whose fire permission is absent has whichever of those it would wear pulled 62% of the way to `color 0.52 0.55 0.58 1`, which keeps the hue so the player's envelope and the enemy's stay told apart while both are disengaged. Highlight and desaturation are read from the marker's `markerPortHoldsTarget`/`markerStarboardHoldsTarget` and `markerFirePermission` and never from the reload, so the three channels are independent: `testFiringEnvelopeFillAndHighlightAreIndependent` produces all four combinations of loaded-or-reloading against target-inside-or-not, which includes the two the issue names — a full unhighlighted wedge and a part-filled highlighted one — and shows that neither channel moves when the other does.
- **The wedge sits at z 0.25.** The hull's own extent reaches 0.125 and the navigation overlays sit at 0.1 to 0.2, so a wedge at those heights would be inside the hull it is anchored to. 0.25 is above all of them and still below issue 06's reticles at 0.3, so the two heights are distinct, cannot z-fight, and the locked ring stays visible on a target that is inside a filled envelope. Issue 06's reticle radius and height are untouched.
- **A disabled ship and a finished engagement draw no wedge, and the rule is the ship's own state.** A destroyed hull has no guns left to draw for, and a finished engagement can no longer fire, so a lit wedge there would promise a volley the volley phase will never send. The other ship's wedges keep being drawn in both cases, because neither rule is the scene's. In the shipped duel a disabled hull and a finished status arrive together; the code does not depend on that.
- **Neither the mesh count nor the primitive count of the opening scene changed.** Both ships are unlocked at tick 0, so the opening scene is still exactly six meshes and six primitives, and `testInitialBattleRenderScene` asserts that plus the absence of any envelope, with the reason in the test. The number that did need stating is the locked scene's: nine primitives — six hull and heading meshes, two wedges, and issue 06's locked reticle, which the same lock earns. `testFiringEnvelopeAppearsPerLockedBroadside` pins it; no exact assertion was loosened.
- **The wedge is opaque, because the renderer has no blending.** `batchExecutorSource` enables the depth test and never `gl.BLEND`, so every primitive's alpha is written but not composited, and a wedge has to be a solid shape. Two consequences the picture carries and the acceptance criteria do not mention: a wedge covers the hull it is anchored to where they overlap (the apex region, roughly the hull's waist), and it is drawn over the navigation overlays at 0.1 to 0.2 where they cross it. Enabling blending would change every existing stroke's appearance and is a renderer decision of its own, not a rider on this issue.
- **`scan-hover-positions` and `diagnosis-hover-perf` gain `FlorDoMar.Client.GunPanel` in their `other-modules`.** They list `BattleScene`, which now imports that module for the shared reload reading; without the listing a fresh build warns `-Wmissing-home-modules` for a throwaway target. The pre-existing warnings in those files are untouched.
