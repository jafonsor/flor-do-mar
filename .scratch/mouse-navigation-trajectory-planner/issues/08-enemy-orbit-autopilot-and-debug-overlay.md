Status: ready-for-agent

# Enemy Orbit Autopilot And Debug Overlay

## What to build

Add the first non-player autopilot behavior using normal navigation orders. The enemy ship should orbit around its starting position by issuing ordinary navigation orders to successive waypoints around a fixed-radius circle. Add a client debug checkbox in the engagement setup overlay, defaulting on, that controls whether enemy/autopilot trajectories and speed rings are rendered.

The debug setting is client state only. It applies immediately and does not require relaunching the engagement.

## Acceptance criteria

- [ ] Enemy orbit autopilot issues ordinary navigation orders rather than special movement.
- [ ] The first orbit center is the enemy starting position.
- [ ] The first orbit uses a fixed first-playable radius.
- [ ] Orbit autopilot issues the next waypoint after reaching the current one.
- [ ] Enemy/autopilot trajectory and speed ring render when debug overlays are enabled.
- [ ] Enemy/autopilot trajectory and speed ring are hidden when debug overlays are disabled.
- [ ] Debug checkbox appears in the engagement setup overlay and defaults on.
- [ ] Changing the debug checkbox applies immediately to the current engagement without pressing Launch Engagement.
- [ ] Debug checkbox state persists for the current client session and does not persist beyond it.
- [ ] Tests cover orbit order issuance, debug flag state, and render-scene output for debug overlays.

## Blocked by

- `.scratch/mouse-navigation-trajectory-planner/issues/04-render-active-navigation-trajectory-and-speed-ring.md`
- `.scratch/mouse-navigation-trajectory-planner/issues/07-handle-navigation-edge-cases.md`
