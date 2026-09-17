# Create Reflex WebGL Wrapper

Status: ready-for-agent

## Summary

Create a small Reflex-friendly WebGL rendering layer for the tactical battle view.

## Background

WebGL should render combat snapshots, but combat rules must remain outside the renderer. Reflex should own UI wiring, commands, subscriptions, and playtest controls.

## Scope

- Add a canvas or WebGL surface to the Reflex client.
- Create a small wrapper that accepts combat snapshots as render input.
- Render two simple ship markers with heading.
- Render enough spatial context to understand range and movement.
- Keep renderer state separate from combat simulation state.

## Acceptance Criteria

- The browser page shows a WebGL battle view.
- Two ships can be rendered from a combat snapshot.
- Ship position and heading update when snapshots change.
- Rendering code does not own combat rules.
- The wrapper exposes a small interface that is usable from Reflex.

## Notes

Visual polish is out of scope. Simple geometric ships are enough for the first tracer bullet.
