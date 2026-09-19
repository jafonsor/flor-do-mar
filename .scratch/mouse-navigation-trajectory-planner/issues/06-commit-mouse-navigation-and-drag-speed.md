Status: ready-for-agent

# Commit Mouse Navigation And Drag Speed

## What to build

Wire the mouse navigation gesture into Combat API commands. Primary mouse down on the battle view commits the currently selected reachable waypoint immediately so the ship starts maneuvering. Dragging after mouse down previews a selected post-waypoint speed on the speed ring. Mouse release updates the active order's pending post-waypoint speed; if the waypoint has already cleared, release sets the ship's current target speed.

This replaces player-facing heading and sail controls. Broadside buttons remain.

## Acceptance criteria

- [ ] Primary mouse down over the battle view submits a navigation order immediately.
- [ ] A plain click uses inherited arrival speed as post-waypoint speed.
- [ ] Drag distance from the reachable waypoint center selects speed from stopped to maximum speed.
- [ ] Drag direction has no gameplay meaning beyond selecting radial speed.
- [ ] Mouse release updates pending post-waypoint speed while the waypoint is active.
- [ ] Mouse release sets current target speed if the waypoint has already cleared.
- [ ] New mouse navigation orders replace active navigation orders immediately.
- [ ] Player-facing heading and sail buttons are removed or no longer used for movement.
- [ ] Broadside firing buttons remain available and continue to work.
- [ ] Tests cover mouse-down commit, click-without-drag, drag-release speed selection, release-after-arrival speed behavior, and order replacement.

## Blocked by

- `.scratch/mouse-navigation-trajectory-planner/issues/05-preview-replacement-navigation-from-mouse-hover.md`
