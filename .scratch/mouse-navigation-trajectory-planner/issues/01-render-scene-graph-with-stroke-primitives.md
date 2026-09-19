Status: ready-for-agent

# Render Scene Graph With Stroke Primitives

## What to build

Evolve the battle renderer from a flat mesh list into a small 3D render scene graph while keeping the existing battle view working. The scene graph should support hierarchical groups, existing ship meshes, quaternion-backed 3D transforms, and flat stroke-like primitives that can represent trajectory paths and speed rings as generated triangle geometry rather than WebGL line primitives.

This slice should be independently verifiable through render-scene tests: current ships still render, and simple stroke paths and ring strokes can be expressed as generic render nodes.

## Acceptance criteria

- [ ] Existing ship rendering still works through the new scene graph representation.
- [ ] Render nodes support hierarchical transforms with recursive world-matrix composition.
- [ ] Rotations are quaternion-backed internally, even if helper constructors expose simpler rotation APIs.
- [ ] Stroke paths are represented as flat generated triangle geometry in scene space, not WebGL lines and not camera-facing billboards.
- [ ] Ring strokes are represented as flat generated triangle geometry in scene space.
- [ ] Stroke-like primitives can be placed slightly above the water plane using ordinary 3D transforms.
- [ ] Render-scene tests cover scene graph traversal, transform composition, stroke path output, and ring stroke output.

## Blocked by

None - can start immediately
