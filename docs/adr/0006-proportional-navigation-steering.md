# ADR-0006: Proportional Navigation Steering

Status: Accepted

Date: 2026-09-23

## Context

ADR-0002 committed navigation orders to a planner whose projected trajectory must
match executed movement. Executing an order meant aiming at the reachable waypoint
and choosing a target yaw rate, and that choice was a relay: full rudder authority
in the sign of the heading error, with a 0.001 degree deadband. Yaw rate then
accelerated toward that command at `yaw_acceleration`.

That loop hunts. While the heading error is falling the relay still commands full
authority, so when the error crosses zero the ship is carrying its full turn rate
and must be decelerated at `yaw_acceleration`. It therefore overshoots its bearing
by at least

```
yaw_rate^2 / (2 * yaw_acceleration)
```

degrees. A waypoint bearing rotates back toward the ship as it drifts, so the error
sign flips again and the ship repeats the stroke the other way. Against the shipped
config (`turn_rate 30 deg/s`, `yaw_acceleration 10 deg/s^2`) each reversal carries
the ship 35 to 50 degrees past its bearing: one order to a point 22 degrees off the
bow produced three turn reversals and a path 1.45x the direct distance, and the
client drew it as a sinusoidal weave rather than one committed curve.

The instability is in the control law, not the aiming geometry. The bearing to a
distant waypoint rotates at roughly 1 degree per second while the ship can turn 30,
so the target never outruns the ship. It is also not yaw inertia by itself: inertia
is what makes the relay overshoot, but a rate command that tapers into the bearing
is stable with the same inertia.

Below `ideal_turn_speed` the fault hides, because rudder authority scales the
command down with speed. That is why the reported symptom began as a straight run
and only became a weave once the ship reached cruise speed.

## Decision

Command yaw rate proportionally to the heading error, saturated at full rudder
authority:

```
targetYawRate = 0                                        -- inside the deadband
              | clamp (-authority) authority (error / navigationHeadingCorrectionSeconds)
```

`authority` is `turn_rate * rudderAuthority speed` as before, so the existing
rudder, speed, and yaw-inertia model is untouched. `navigationHeadingCorrectionSeconds`
is the horizon over which a full-authority turn would null the current error, and
the gain is its reciprocal. Two seconds keeps most of an approach inside the
proportional band while still commanding full rudder for large errors.

The deadband and the "no turn intent means zero target yaw rate" rule are kept:
they are what lets a ship without a navigation order ease out of its turn according
to yaw inertia instead of holding a command.

## Consequences

- A navigation order produces one committed turn, and the settled path runs at the
  waypoint: the reported weave collapses to zero turn-direction reversals, the
  off-bow example clears in 21 ticks instead of 33, and its path drops from 1.453x
  to 1.005x the direct distance.
- Closed-loop damping is `1 / (2 * sqrt (yaw_acceleration / correctionSeconds))` and
  is independent of speed, so tuning does not have to be re-solved per boat speed.
- Arrival gets more accurate rather than less: the order-clearing test still judges
  by turning-circle geometry, and ships now approach their waypoint straight.
- `navigationHeadingCorrectionSeconds` is a handling surface, not a magic number.
  Lowering it toward zero re-creates the relay and its overshoot; raising it turns
  earlier and more gently but delays large turns.
- Test fixtures that hand-write movement physics must use realistic
  `yaw_acceleration`. The `navigationMovement` fixture's 180 makes a relay look
  calm because its overshoot is 2.5 degrees; the packaged 10 makes the same law
  weave. Movement bugs are reproduced against the shipped config.
