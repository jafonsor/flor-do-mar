# Model Minimal Combat Domain

Status: ready-for-agent

## Summary

Implement the first combat domain model and fixed-tick simulation for a caravela duel.

## Background

The first playable scenario is one Portuguese caravela versus another Portuguese caravela. The win condition is hull disabled only. Broadside damage is intentionally simple: fixed damage when range, firing arc, and reload cooldown allow it.

## Scope

- Define ship identity, position, heading, speed or sail state, hull integrity, and reload state.
- Define wind state in the simulation.
- Define player commands for heading or sail changes and firing a broadside.
- Implement a fixed-tick state transition function.
- Validate broadside range, firing arc, and reload cooldown.
- Apply fixed hull damage.
- Mark the scenario terminal when a ship's hull integrity reaches zero.

## Acceptance Criteria

- The simulation can advance deterministically from an initial caravela duel state.
- Commands are applied through explicit command values.
- Broadside firing succeeds only when constraints pass.
- Hull damage and reload cooldown are observable in simulation state.
- A disabled hull ends the scenario.
- Unit tests cover at least tick advancement, valid broadside damage, invalid broadside due to range or arc, reload cooldown, and terminal hull state.

## Notes

Do not implement morale, boarding, projectile travel time, accuracy, ammunition types, crew abilities, or loadout configuration yet.
