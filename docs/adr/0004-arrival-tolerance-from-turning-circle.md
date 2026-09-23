# ADR-0004: Arrival Tolerance Derived From Turning Circle

Status: Accepted

Date: 2026-09-22

## Context

ADR-0002 committed the simulation and the preview to one kinematically constrained
planner that produces projected trajectories within a ship's speed, rudder
authority, and turn-radius limits, and made preview/execution mismatch a bug.

Anchoring that planner was `navigationArrivalRadius`, a fixed 1 world unit used to
decide when a ship had reached its waypoint. It did not hold. A ship commits to one
heading for a whole tick and only then re-aims, so it approaches a waypoint along a
polygon whose chords pass the waypoint by a distance set by the ship's own turning
circle. With the shipped runtime config (`tick_seconds 0.8`, `battle_speed 4`,
`turn_rate 30 deg/s`, turning radius 7.64) a ship closed no closer than 2.08 units
to its waypoint and orbited it forever.

Because a cleared order is also what lets the enemy orbit autopilot advance to its
next waypoint, the autopilot could never leave waypoint one: the enemy circled its
start position while the player sailed away. The planner shared the same arrival
test, so it never terminated by arriving either — it exhausted its 2000-tick safety
cap and emitted 2001 trajectory samples per frame, which the client then marshalled
to the browser on every pointer move.

The fixed radius cannot be repaired by tuning. Measured across a sweep of
`battle_speed` and `turn_rate`, the closest approach stays proportional to the
turning radius — roughly 0.82 of it at `turn_rate 30`. Satisfying a fixed radius of
1 would need a turning circle below about 1.2 units, around `turn_rate 188` at
`battle_speed 4`, which no sailing ship should have.

## Decision

Derive the arrival tolerance from the ship's manoeuvrability rather than fixing it
in world units:

```
arrivalTolerance = max navigationArrivalRadius
                       (turningRadius * sin (min (pi/2) requiredHeadingChange))
```

`turningRadius` is sized at `movementBattleSpeed`, the speed a reachable waypoint
is chosen against, so the tolerance stays consistent with the waypoint it judges.
`requiredHeadingChange` is the angle between the ship's heading and the bearing to
the waypoint; the sine of it is the miss a chord of that turn produces. The angle
is clamped at 90 degrees so the tolerance never exceeds one turning radius, and
`navigationArrivalRadius` remains the floor.

The intent is that a ship pointed at its waypoint needs almost no turn and must
still arrive accurately, while a ship on a hard orbit cannot do better than its
circle allows and is accepted at that limit.

## Consequences

- Arrival is measured against what the ship can physically achieve, so it no longer
  depends on tuning values staying inside an undocumented range.
- The enemy orbit autopilot advances through waypoints and the duel stays bounded;
  the planner terminates by arriving in ~25 samples instead of 2001.
- A ship's turning circle is now load-bearing for navigation correctness, not only
  for how movement looks. Widening it without reconsidering this tolerance will
  strand ships again.
- `turn_rate` and `yaw_acceleration` remain a coupled pair: a ship cannot use a turn
  rate it cannot accelerate into, so raising one without the other changes nothing.
- The tolerance is a judgement about when a ship has "arrived", so it is a tuning
  surface. It should be revisited if turning circles change substantially.
