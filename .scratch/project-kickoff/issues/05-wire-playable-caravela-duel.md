# Wire Playable Caravela Duel

Status: ready-for-agent

## Summary

Integrate the Reflex UI, Local Combat API, fixed-tick simulation, and WebGL wrapper into the first playable caravela duel.

## Background

This is the vertical tracer bullet for Flor do Mar. It should prove that the client can start a local scenario, render snapshots, submit commands, advance combat, resolve broadside damage, and show the end state.

## Scope

- Add a start/reset control for the caravela duel.
- Display hull integrity, reload state, and scenario status.
- Let the player issue a heading or sail command.
- Let the player fire a broadside when allowed.
- Advance the simulation on fixed ticks through `LocalCombatApi`.
- Render state updates in the WebGL battle view.
- Display victory or defeat when a hull reaches zero.

## Acceptance Criteria

- A developer can run the client and play the minimal caravela duel.
- The player can maneuver their ship.
- The player can fire a broadside under valid range, arc, and cooldown conditions.
- Enemy hull integrity decreases after successful broadside fire.
- The scenario ends when one ship reaches zero hull integrity.
- The UI does not bypass `CombatApi` to change combat state.

## Notes

The opposing ship may be stationary or scripted for this first integration. A smarter opponent is not required.
