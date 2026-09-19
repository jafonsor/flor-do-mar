# ADR-0003: 3D Render Scene Graph

Status: Accepted

Date: 2026-09-19

## Context

The first battle renderer used a flat list of cube meshes with 2D rotation around Z. Navigation previews, speed rings, debug overlays, and future 3D battle presentation need richer render primitives and hierarchical transforms without putting battle-specific drawing rules into the WebGL backend.

## Decision

Evolve the render layer toward a small Three.js / React Three Fiber-inspired scene graph. The battle scene should produce generic render nodes such as groups, meshes, strokes, stroke paths, and ring strokes; the WebGL renderer should traverse those nodes, compose parent and local transforms, and draw the supported primitives.

Transforms should be real 3D transforms from the start. Rotations are quaternion-backed internally, even if convenience APIs later accept Euler-style inputs.

Stroke paths and ring strokes are flat generated triangle geometry in scene space, not camera-facing billboards. If a camera views a flat stroke edge-on and it becomes thin or disappears, that is acceptable.

## Consequences

- Battle-specific concepts like projected trajectories, active orders, hover previews, speed rings, and debug overlays stay in the battle scene/view model.
- The renderer remains a generic WebGL edge that consumes render primitives rather than combat concepts.
- Stroke-like primitives should be rendered as generated triangle geometry for graphical quality, not WebGL line primitives.
- Stroke-like primitives should behave as flat world geometry rather than screen-facing overlays.
- Hierarchical transforms require matrix-stack-style traversal or equivalent recursive world-matrix composition.
- The game can remain top-down initially without baking 2D-only assumptions into the render architecture.
