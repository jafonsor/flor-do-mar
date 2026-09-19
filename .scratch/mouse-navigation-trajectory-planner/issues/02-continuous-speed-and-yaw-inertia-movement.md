Status: ready-for-agent

# Continuous Speed And Yaw Inertia Movement

## What to build

Replace the movement model's three sail-speed targets and low-speed turn factor with continuous target speed, linear rudder authority, signed yaw rate, and yaw inertia. Ships should accelerate and decelerate toward target speed, yaw rate should accelerate toward the internally chosen target yaw rate, and stopped ships should have no rudder authority until they build forward speed.

This slice should be verifiable through the combat simulation and Combat API snapshots before any mouse UI exists.

## Acceptance criteria

- [ ] Boat movement tuning includes ideal turn speed and yaw acceleration.
- [ ] The old minimum low-speed turn factor is no longer the active rudder authority model.
- [ ] Target speed is continuous from stopped to maximum speed and never negative.
- [ ] Rudder authority is zero while stopped and rises linearly to full authority at ideal turn speed.
- [ ] Ship state stores signed current yaw rate.
- [ ] Ship snapshots expose current yaw rate and continuous movement state needed by the planner.
- [ ] With no active waypoint or turn intent, target yaw rate is zero and the ship eases out of turns according to yaw inertia.
- [ ] Tests cover zero-speed no-turn behavior, straight-ahead acceleration before turning, yaw-rate acceleration, and continuous speed acceleration/deceleration.

## Blocked by

- `.scratch/hot-reloadable-boat-physics/issues/03-run-configured-movement-physics.md`
