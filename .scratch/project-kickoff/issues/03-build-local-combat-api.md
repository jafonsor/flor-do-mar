# Build Local Combat API

Status: ready-for-agent

## Summary

Wrap the combat simulation in a server-like local API that the Reflex client can use without directly mutating simulation internals.

## Background

The frontend should talk to combat through an API boundary that can later be replaced by real server calls. The first implementation is local and in-process.

## Scope

- Define the `CombatApi` boundary for starting scenarios, submitting commands, and observing snapshots or events.
- Implement `LocalCombatApi` around the minimal combat simulation.
- Define a snapshot type suitable for UI rendering.
- Add the caravela duel as a named local scenario.
- Keep the API shape compatible with a future remote implementation.

## Acceptance Criteria

- The Reflex client can start the caravela duel through the API boundary.
- Commands enter the simulation through the API boundary.
- The UI can observe snapshots without direct access to internal mutable simulation state.
- The API reports terminal scenario state.
- Tests can exercise `LocalCombatApi` without a browser.

## Notes

The API does not need HTTP or WebSocket transport in this issue. The goal is a local boundary with a server-shaped interface.
