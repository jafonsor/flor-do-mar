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
