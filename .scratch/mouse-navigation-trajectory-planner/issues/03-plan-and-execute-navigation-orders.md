Status: ready-for-agent

# Plan And Execute Navigation Orders

## What to build

Add navigation orders as command-based movement intent for any ship. A navigation order records the requested waypoint for diagnostics, commits a reachable waypoint for simulation, owns pending post-waypoint speed, and is executed by the same kinematically constrained trajectory planner used for preview.

The planner result should expose the selected trajectory only, including samples and metadata, without exposing discarded internal alternatives. The simulation should move the ship toward the committed reachable waypoint and clear the waypoint on arrival while preserving target speed intent.

## Acceptance criteria

- [ ] Combat commands can issue a navigation order for any ship.
- [ ] A navigation order stores requested waypoint metadata and a committed reachable waypoint.
- [ ] Command-time planning clamps impossible/tighter-than-possible requests to a reachable waypoint.
- [ ] The committed reachable waypoint remains fixed after command time.
- [ ] Planner results include requested waypoint metadata, reachable waypoint, clamped status, arrival speed, and selected trajectory samples.
- [ ] Trajectory samples include position, heading, speed, yaw rate, and time or tick offset.
- [ ] Simulation execution and projection use the same planner/integration model.
- [ ] Arrival clears the active waypoint and leaves target speed intent.
- [ ] New navigation orders replace active navigation orders instead of queueing waypoint paths.
- [ ] Tests prove preview samples match subsequent simulation movement from the same initial state and order.

## Blocked by

- `.scratch/mouse-navigation-trajectory-planner/issues/02-continuous-speed-and-yaw-inertia-movement.md`
