# PRD: Mesh Rendering Pipeline For Tactical Battle View

Status: ready-for-agent

## Problem Statement

The tactical battle view currently renders combat snapshots with immediate WebGL scissor rectangles. That proves a canvas can show the duel, but it does not provide the camera, mesh, shader program, geometry, material, and render-update structure needed for richer battle rendering.

The developer needs the tactical battle view to move to a small React Three Fiber-like rendering layer while preserving the existing separation between combat simulation and browser rendering.

## Solution

Render the tactical battle view through a declarative scene value. Each combat snapshot is translated into a pure render scene containing an orthographic camera and mesh descriptions. The renderer initializes WebGL resources once for the canvas, then draws updated scene values as snapshots change.

The first scene uses direct combat-world units, a fixed orthographic camera centered on the initial duel, real cube geometry under the hood, a single internal basic material shader pipeline, and mesh instances for ships plus heading markers. Ship hull integrity affects color by tinting damaged ships toward dark gray.

## User Stories

1. As a developer-playtester, I want the tactical battle view to render through a camera, so that ship positions are framed by a world-space view instead of canvas pixel math.
2. As a developer-playtester, I want ships to be represented as meshes, so that battle rendering can grow beyond immediate rectangle drawing.
3. As a developer-playtester, I want cube geometry for ship markers, so that the renderer exercises a real mesh pipeline without waiting for final art.
4. As a developer-playtester, I want a shader program pipeline, so that rendering uses explicit vertex and fragment shaders.
5. As a developer-playtester, I want a basic material, so that mesh colors can be controlled without introducing lighting, textures, or custom shader APIs.
6. As a developer-playtester, I want shader programs and buffers to initialize once per canvas, so that every snapshot update does not recompile shaders or recreate shared geometry.
7. As a developer-playtester, I want each combat snapshot to produce a fresh declarative render scene, so that rendering remains snapshot-driven and easy to reason about.
8. As a developer-playtester, I want combat positions to map directly to render positions, so that the tactical battle view remains faithful to the simulation.
9. As a developer-playtester, I want heading zero to point along positive X and heading ninety to point along positive Y, so that rendered movement matches the combat model.
10. As a developer-playtester, I want the first camera to use fixed framing, so that the initial implementation stays predictable while the render pipeline is being proven.
11. As a developer-playtester, I want the fixed camera centered on the initial duel, so that both ships are visible with room around them.
12. As a developer-playtester, I want ships to rotate with their headings, so that movement direction is visible from the ship mesh itself.
13. As a developer-playtester, I want a separate heading marker ahead of each ship, so that heading remains readable with simple cube geometry.
14. As a developer-playtester, I want player and enemy ships to have distinct colors, so that identity is readable at a glance.
15. As a developer-playtester, I want damaged ships to tint toward dark gray, so that hull integrity has an immediate visual cue.
16. As a developer-playtester, I want exact hull values to remain in the surrounding UI, so that the mesh scene can stay uncluttered.
17. As a developer-playtester, I want no grid in the first mesh scene, so that the initial render pipeline focuses on ships and heading markers.
18. As a developer-playtester, I want no range bar in the first mesh scene, so that overlays and extra primitive types can be introduced deliberately later.
19. As a developer-playtester, I want WebGL to stay behind the frontend rendering layer, so that combat simulation remains independent from browser APIs.
20. As a developer-playtester, I want renderer resource management to stay internal, so that battle rendering code describes scenes rather than GPU buffers.
21. As a future renderer contributor, I want the scene API to have camera, mesh, geometry, material, and transform concepts, so that later rendering features have obvious extension points.
22. As a future renderer contributor, I want the first geometry to be a real unit cube, so that later camera tilt, height, normals, or lighting can build on the same abstraction.
23. As a future renderer contributor, I want the material system to start closed and minimal, so that custom shader support is not designed before there is a concrete need.
24. As a future renderer contributor, I want transforms to include position, rotation, and scale, so that scene values can express ship placement without leaking WebGL details.
25. As a future renderer contributor, I want render updates to draw through an existing renderer value, so that the Reflex lifecycle is explicit and resource churn is avoided.

## Implementation Decisions

- Keep combat semantics tactically 2D while rendering through a mesh and camera abstraction.
- Use an orthographic camera rather than a perspective camera for the first mesh scene.
- Use direct combat-world units as render units. Combat points map to mesh positions without pixel conversion.
- Use fixed camera framing centered around the initial duel midpoint.
- Use a world viewport close to the existing canvas aspect ratio, with enough room around the initial ships.
- Introduce a declarative render scene value containing a camera and a list of meshes.
- Introduce mesh descriptions containing geometry, material, and transform data.
- Keep renderer resource management internal. The battle view describes scene values and does not manage shader programs, buffers, or locations.
- Compile a single internal basic shader program during renderer initialization.
- Create shared cube geometry buffers during renderer initialization.
- Reuse the basic shader program and cube buffers across snapshot renders.
- Update per-frame and per-mesh uniforms during drawing.
- Use real 3D cube geometry centered at the origin, even though the first camera reads as a top-down orthographic tactical view.
- Render each ship as a flattened, scaled cube.
- Rotate ship meshes around the Z axis using ship heading.
- Render each heading marker as a small cube offset ahead of its ship along the heading vector.
- Color player and enemy ships distinctly.
- Tint damaged ships toward dark gray using hull integrity.
- Keep grid rendering, range rendering, lighting, textures, normals, custom material shaders, and camera auto-framing out of the first pass.
- Preserve the existing Combat API and snapshot boundary. The combat simulation must not depend on WebGL, Reflex, or rendering types.

## Testing Decisions

- Good tests should exercise externally observable behavior: scene values produced from battle snapshots, transform/color decisions, and renderer lifecycle boundaries where practical.
- Prefer testing the pure scene-building seam over WebGL internals. A battle scene converted into a render scene should expose camera settings, mesh count, ship transforms, heading marker transforms, and material colors.
- Add focused pure tests for tactical battle view scene construction if the existing test suite can depend on client modules without pulling in browser-only dependencies.
- If client modules remain executable-only and difficult to test from the existing suite, keep compile verification as the first safety check and consider extracting pure scene construction into a testable module in a follow-up.
- Existing combat tests remain prior art for testing domain behavior outside the browser. This feature should not alter those combat tests except where build configuration requires a new testable seam.
- WebGL shader compilation and browser canvas drawing should be verified by building/running the client rather than brittle tests over internal implementation details.

## Out of Scope

- Perspective camera rendering.
- Camera auto-framing.
- Tactical grid rendering.
- Range bar rendering.
- Text labels inside the canvas.
- Broadside arc visualization.
- Wind visualization.
- Lighting, normals, texture mapping, loaded ship models, or final art assets.
- Custom user-provided shaders.
- Multiple geometry types beyond cube geometry.
- Changes to combat simulation, Combat API semantics, command handling, or tick behavior.

## Further Notes

This feature follows the accepted architecture direction: Reflex and WebGL consume snapshots and submit commands at the frontend edge, while combat rules remain independent of browser rendering.

The implementation should make the shader pipeline real now, but keep the material system intentionally small until the tactical battle view needs lighting, textures, or authored assets.
