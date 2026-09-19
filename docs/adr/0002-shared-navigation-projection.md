# ADR-0002: Shared Navigation Projection

Status: Accepted

Date: 2026-09-18

## Context

Flor do Mar's tactical movement is moving from heading and sail buttons to mouse-issued navigation orders. The player needs to see the projected trajectory before committing an order, including the ship's current speed, rudder authority, yaw inertia, turn speed, acceleration, deceleration, reachable waypoint, arrival speed, and post-waypoint speed. This trajectory should be planned from the ship's movement constraints, not drawn as a direct cursor path or approximated as the primary domain model by unrelated steering candidates.

## Decision

Represent movement as command-based navigation orders, not direct steering. A navigation order targets a reachable waypoint and a post-waypoint speed in the continuous range from stopped to the ship's maximum speed.

Calculate projected trajectories with a kinematically constrained trajectory planner in pure combat/domain logic shared by both the simulation and the client preview. The preview is a prediction of the same movement the simulation will execute; mismatch between projected and actual movement is a bug unless battle conditions change between preview and execution.

The tactical battle view may clamp an unreachable cursor position to the nearest reachable waypoint. Clicking commits the reachable waypoint shown by the projection, not the raw cursor position.

The planner may use target yaw rates internally to account for yaw inertia, but direct yaw-rate commands are not part of the first waypoint navigation UI.

When trajectory samples are exposed or rendered, they should describe only the selected trajectory that will be used. Alternative planner candidates or discarded search branches should not be part of the player-facing projection.

Mouse down commits the reachable waypoint immediately so the ship starts maneuvering at once. The active navigation order owns its pending post-waypoint speed. If the player drags before release, release updates that pending post-waypoint speed while the waypoint is active; if the waypoint has already cleared, the same gesture sets the ship's current target speed. This should not introduce a general queued-command scheduler or multi-waypoint path queue.

## Consequences

- The client can render dashed trajectory previews and speed rings without owning movement rules.
- The Combat API remains command-based and compatible with future authoritative synchronization.
- Boat movement tuning must model rudder authority, yaw inertia, ideal turn speed, acceleration, deceleration, and maximum speed well enough for projection and execution to share one solver.
- The old `minimum_turn_speed_factor` tuning should be replaced by a rudder authority model that can express zero authority while stopped.
- New navigation orders replace previous movement orders immediately.
- Broadside firing remains a separate explicit command for now.
