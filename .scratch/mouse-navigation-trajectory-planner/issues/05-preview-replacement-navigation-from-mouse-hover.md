Status: ready-for-agent

# Preview Replacement Navigation From Mouse Hover

## What to build

Add client-side battle-view hover preview for player navigation. Pointer movement over the battle view should convert screen coordinates to battle-space points, run the shared planner from the latest actual player ship state, and render the selected hover trajectory and speed ring. If an active order already exists, show the hover replacement preview alongside the active trajectory.

Pointer details stay in the client. Combat/domain receives only battle-space points and semantic planner requests.

## Acceptance criteria

- [ ] A client input adapter turns raw pointer movement over the battle view into semantic hover intent.
- [ ] Screen-to-world conversion lives with battle view/camera code rather than combat/domain code.
- [ ] Hover preview starts from the latest actual player ship state.
- [ ] Hover preview uses the same planner result shape as active orders.
- [ ] Hover preview clamps unreachable cursor positions to the selected reachable waypoint.
- [ ] Hover speed ring shows expected arrival speed and maximum speed.
- [ ] Hover preview appears alongside an active trajectory rather than replacing it.
- [ ] Hover preview is hidden while setup overlay is open, while pointer is over other UI controls, and after scenario finish.
- [ ] Tests cover pure input-intent state where practical and render-scene output for hover trajectory and speed ring.

## Blocked by

- `.scratch/mouse-navigation-trajectory-planner/issues/01-render-scene-graph-with-stroke-primitives.md`
- `.scratch/mouse-navigation-trajectory-planner/issues/03-plan-and-execute-navigation-orders.md`
- `.scratch/mouse-navigation-trajectory-planner/issues/04-render-active-navigation-trajectory-and-speed-ring.md`
