Status: ready-for-agent

# Gun Panel and Click to Lock

## What to build

The player-facing controls for the new firing model: a screen-anchored gun panel, and clicking a ship to lock it.

**The panel** is HTML above the canvas, in the same idiom as the existing panels and the setup overlay. It carries the fire-at-will toggle and the reload circle. The reload circle fills as the shared reload progresses and shows armed state by colour **immediately on click**, before the order is processed on the next tick, so the player can see their input was received. Disengaging lets the outer sweep finish rather than snapping back, so the final volley visually completes; when the sweep finishes the circle empties and the control becomes clickable again.

**The overlay must not swallow the canvas.** The container passes pointer events through, and only its interactive controls capture them. A full-canvas HTML overlay that captures events would break navigation, which depends on the canvas receiving mousedown, mousemove, and mouseup.

**Clicking a ship locks it; clicking the locked ship unlocks it.** Pressing on a ship and releasing without moving toggles the lock. Pressing and dragging still issues a navigation order, including when the drag starts on a hull, so the existing gesture is preserved. The existing gesture model already distinguishes the two: a plain click leaves the selected post-waypoint speed unset and a drag sets it.

**Hit-testing uses a screen-space radius** around each ship centre rather than the hull rectangle, so hulls stay clickable as zoom changes. This needs no unit conversion — the pointer already arrives in canvas pixels, and the existing screen-to-battle conversion covers the rest.

**A hover circle marks a ship that would lock if clicked**, and the locked ship gets a ring of the same size in a different colour, so the transition on click is a colour change rather than a shape change. Both are canvas nodes derived from the client's hover and lock state. Do not add a dashed line to the target.

**Clicking the player's own ship does nothing.** The client does not send a lock on its own hull, and the simulation refuses one if it does.

The panel also carries a lock control for the currently hovered or locked ship, so locking is reachable without the canvas gesture. That control appears only when a lockable ship has been hit-tested or is already locked, so the panel never offers a lock action with no target.

Remove the "Fire port" and "Fire starboard" buttons.

## Acceptance criteria

- [ ] A gun panel renders above the canvas with a fire-at-will toggle and a reload circle.
- [ ] The overlay container passes pointer events through, and canvas navigation still works with the panel present.
- [ ] The reload circle's fill tracks reload progress and reaches full when the guns are loaded.
- [ ] The circle's colour changes on click, before the order has been processed on a tick.
- [ ] Disengaging mid-reload lets the sweep complete rather than resetting immediately, and the control becomes clickable again once the sweep finishes.
- [ ] Clicking an enemy hull toggles its lock state; clicking it again unlocks it.
- [ ] Clicking empty water still issues a navigation order.
- [ ] Dragging, including a drag that starts on a hull, still issues a navigation order and sets post-waypoint speed.
- [ ] Clicking the player's own hull sends no command and issues no navigation order.
- [ ] A hover circle renders on a ship that would lock if clicked, and a ring renders on the locked ship.
- [ ] The hover and locked markers are the same size and differ by colour.
- [ ] The lock control only appears when a lockable ship is hovered or locked.
- [ ] The fire port and fire starboard buttons are gone.
- [ ] Tests cover the gesture split — click toggles the lock, drag navigates — through the existing pointer-intent model, and assert no lock command is produced for the player's own hull.

## Blocked by

- `.scratch/firing-envelope-and-lock/issues/01-model-locked-targets-and-fire-permission.md`
- `.scratch/firing-envelope-and-lock/issues/04-expose-per-ship-gunnery-state.md`

## Notes for whoever implements it

- The gesture split is decided **at release**, from the mousedown position. The existing navigation gesture already carries whether a speed was selected, which is the signal that separates a click from a drag — reuse it rather than adding a parallel notion of "did the pointer move".
- The reload circle is the only smooth animation in the feature. It lives in the DOM precisely so it can animate without a canvas frame loop, which the client does not have.
- Hit-testing and the hover state belong in the pointer-intent model, which is already exercised by tests without a browser. Keep the ship hit test pure so it is testable at that seam.
- The locked and hover rings are canvas nodes, so they land in the render scene with the rest of the battle view. Keep them above the hull in z, like the existing overlays.

## Decisions recorded by the implementation

Status: implemented in the issue 06 commit. Every acceptance criterion above is met.

- **The reticle is one number, and that is the point.** `reticleRadiusPixels = 24` in `FlorDoMar.Client.BattleInput`; `screenReticleRadius` converts it to battle units at the camera and the canvas size the pointer actually arrives in, and `pointerSample` carries that radius alongside the battle point in every pointer intent. The click hit test (`hullAtReticle`), the hover ring and the locked ring all use it, so a hover ring is a promise about where the click lands. The world-per-pixel scale depends on the zoom *and* the displayed canvas size, which is why the radius rides with the pointer event rather than being a world constant or a scene literal. The scene draws both rings at `battleSceneReticle`'s radius, which is the last radius the pointer carried.
- **The press records the hull, the release decides.** `navigationReleaseIntent` is the split: a release with a selected speed is a navigation order, and a release without one is a lock when the press landed on a hull that is not the shooter's own, nothing at all when it landed on the shooter's own hull, and a navigation order over open water. The press stores the *raw* hit test result (`hullAtReticle`, which includes the player's own hull) rather than the lock candidate, because "clicked my own ship" and "clicked water" have to be told apart; the hover and lock-candidate question (`reticleShip`, `lockTargetAtSample`) is that same hit test with the shooter's hull filtered out. A test caught this: with the lock-candidate test used for the press, a click on the player's own hull silently became a navigation order.
- **The hover is re-derived on every snapshot, not on every pointer move.** The first cut folded the hover from pointer events alone, and a review caught what that costs: the enemy orbits 4 units a tick while the reticle is about 8.4 world units, so a pointer held still over a moving hull kept a ring on a ship it was no longer over — and because a click hit-tests the press afresh, that click navigated while the ring said it would lock. `BattleView` now holds the last `PointerSample` (cleared on `mouseleave` and on the setup overlay opening) and derives the hover with `zipDynWith (hoveredShipAt PlayerShip) hoverSampleDynamic snapshotDynamic`, where `hoveredShipAt shooter pointer snapshot = lockTargetAtSample shooter snapshot =<< pointer`. The hover is therefore the click's own hit test against the snapshot in hand, so the ring, the press hit test and the panel's lock control cannot disagree, and the scene — which re-renders on every snapshot update — takes the ring away on the tick that moves the ship out from under the pointer. `testReticleHoverFollowsTheSnapshot` pins the rule with no pointer event at all: an unchanged sample on an unchanged snapshot keeps the hover, the same sample against a snapshot whose hull has moved two reticles away clears it, no sample clears it, and the player's own hull is never the hovered ship.
- **The navigation order moved to release.** It used to be emitted on mousedown; it is now emitted on the same mouseup that decides the gesture, so a click on a hull issues no order. Nothing else in the drag path changed: the waypoint is the press position, the post-waypoint speed is the release's selected speed, and the drag speed ring still previews it off the gesture's reachable waypoint.
- **The reload circle's sweep is reload progress, and it is never reset.** The fill is `1 - remaining/total` — empty at the volley that started the reload, full when the guns are loaded — so the issue's "the fill reaches full when the guns are loaded" holds by construction. Disengaging mid-reload does not touch it because the circle reads the reload counter and not the fire permission, and the guns reload whether or not they are permitted to fire: the sweep runs on to full and the toggle becomes clickable to arm again when it gets there. **This is where the issue's wording contradicts itself**: it also says "when the sweep finishes the circle empties", which cannot hold together with the fill reaching full when the guns are loaded. The reading taken is the one the acceptance criteria and the PRD state — the sweep ends *at* full, and "the sweep finishes" means the reload reaches zero — because emptying a full circle would make the circle lie about the state the player is timing their order against.
- **The circle animates with a CSS transition, not a clock.** The fill's `stroke-dashoffset` is written from the snapshot on every tick and the element carries `transition: stroke-dashoffset <tick seconds>s linear`, with the duration taken from `combatSnapshotTickSeconds` so it stays one tick after a config hot reload. The browser interpolates between the snapshots the simulation publishes; no frame loop, no per-frame clock, and nothing in the canvas animation machinery changed.
- **The optimistic toggle is bounded by the tick, not by a timeout.** The click stores `FireAtWillRequest armed tick`; the panel shows that state until a snapshot from a *later* tick arrives. That matters because `combatApiSubmitCommand` immediately publishes a snapshot of the same tick with the command still queued — clearing on "any snapshot update" would have made the optimistic colour last one round trip instead of one tick. When the later tick arrives the request is dropped whether the tick applied it or refused it, so a refused arming reverts to the snapshot instead of sticking. On top of that the control is not clickable to arm while the reload is above zero and is always clickable to disengage, so a refusal is not reachable through the UI at all; the display rule is what makes it harmless if one ever is.
- **The toggle is a real `disabled` button, and the lock control is hidden, not absent.** The lock control is always in the DOM and hidden (`display: none`) when there is no hovered or locked ship, and its click event is filtered by the same view model, so the panel never offers a lock action with no target — including on a hand-built snapshot whose player has somehow locked itself.
- **Both rings are scene nodes at z 0.3.** The hull's own z extent reaches 0.125 (a unit cube scaled to 0.25 in z) and the navigation overlays sit at 0.1 to 0.2, so a reticle at those heights would be buried in the hull it marks. The hover ring is suppressed on the ship that is already locked: a click there releases the lock, so that ship wears the locked ring, and the transition on click is a colour change rather than a shape change.
- **The panel is an overlay inside the battle view's own container.** `battleView` now renders `<div class="battle-view"><canvas …/><div class="gun-panel">…</div></div>`; the container is `position: relative` and the panel `position: absolute` with `pointer-events: none`, and only `.gun-control` asks for events back. Navigation still gets the canvas's own mousedown/mousemove/mouseup, and the canvas element, its id and its size attributes are unchanged.
- **The panel carries no `Player` or `Enemy` text.** The diagnosis harnesses split the body text on those words to find the ship panels (`docs/agents/testing-and-tooling.md`), and the panel now sits *before* them in the document, so a label containing either word would shift the parse to the wrong segment. Its controls say "Fire at will", "Lock"/"Unlock" and a reload `aria-label`. The per-ship gunnery *text* readout stays in the status grid: it is the harness's ground truth for lock, permission and reload, and it is the only place those numbers are labelled per ship.
- **`Main.hs`'s two pre-existing warnings are fixed in this commit** (`-Wname-shadowing` on `now`, which Reflex also exports, and a `-Wtype-defaults` in the `round`), so a warning-free client build is auditable from here on.
- **The fire port and fire starboard buttons were already gone.** Issue 01 deleted `FireBroadside` and took the client's fire buttons with it; nothing in the client references a firing side, and no bridging control was added while the gun panel was missing.
- **The mesh count assertions are untouched.** The reticles are `RingStroke` nodes, not meshes, and the initial scene has neither a hover nor a lock, so the shipped opening scene still flattens to exactly six primitives. No existing exact assertion was loosened.
