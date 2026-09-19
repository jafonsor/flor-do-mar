Status: ready-for-agent

# Render Active Navigation Trajectory And Speed Ring

## What to build

Render a ship's active navigation order in the tactical battle view. The active projected trajectory should be recomputed from the latest actual movement state and shown as the remaining future path. The speed ring should stay anchored to the committed reachable waypoint until arrival and show the pending post-waypoint speed relative to maximum speed.

This slice should make active navigation visible without requiring mouse hover or drag input yet.

## Acceptance criteria

- [ ] Active player navigation trajectory renders as a stroke path using selected trajectory samples from the planner result.
- [ ] Active player speed ring renders as ring strokes anchored to the committed reachable waypoint.
- [ ] Active trajectory is recomputed from latest actual ship state and shows only the remaining future path.
- [ ] The active speed ring remains visible until the waypoint is reached.
- [ ] No wake/history trail is added.
- [ ] Rendered trajectory and speed ring sit slightly above the water plane.
- [ ] Finished scenarios do not show planning overlays.
- [ ] Render-scene tests cover active trajectory and active speed ring output.

## Blocked by

- `.scratch/mouse-navigation-trajectory-planner/issues/01-render-scene-graph-with-stroke-primitives.md`
- `.scratch/mouse-navigation-trajectory-planner/issues/03-plan-and-execute-navigation-orders.md`
