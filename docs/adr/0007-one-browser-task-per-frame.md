# ADR-0007: One Browser Task Per Rendered Frame

Status: Accepted

Date: 2026-09-24

## Context

The battle canvas flickered: frames reached the screen with the trajectory strokes
and speed rings drawn but no ship hulls, heading markers or target markers in them.
Reported from play with screenshots at ticks 0, 1, 4, 5 and 6 — the boats present
at 0, 4 and 6, absent at 1 and 5.

The scene was never the problem. Every render issued exactly six unit-cube draws
(measured: 1272 over 212 renders), and one flickering frame also drew the player's
hover overlay, which is derived from the player's own snapshot in the same scene —
so the snapshot, the FRP graph and the scene graph all still contained the ships.

`renderScene` was the problem. It issued one jsaddle-warp round trip per WebGL call
— `viewport`, `clear*`, `useProgram`, and then per primitive `bindBuffer` x2,
`vertexAttribPointer`, `uniformMatrix4fv`, `uniform4f`, `drawElements` — so a render
was dozens of separate browser tasks and the compositor could present the canvas
between any two of them. A canvas created without `preserveDrawingBuffer` is
cleared once it has been presented, so everything drawn before that boundary was
wiped, and the ships are the **first six primitives of the draw order**: exactly
the primitives that go missing when a boundary lands mid-render. Strokes and rings,
drawn after the boundary, stayed on screen.

Measured with `.scratch/diagnosis/cdp-canvas-flicker.mjs` (idle 6 s, pointer 6 s):
4.7–5.1% of the session had no boats on the canvas across six runs, and a boat-less
frame stayed up until the next render — 49–784 ms — because nothing redraws in
between. A render's own GL calls spanned up to 19.2 ms, which is more than one
60 Hz frame.

ADR-0005 had already removed the per-call *uploads* and the per-event DOM reads,
and left "the number of blocking round trips is now the budget" as the standing
constraint. It did not make a frame atomic.

## Decision

A frame becomes one browser task.

- **`Renderer.hs` collects the frame.** Everything a frame needs — clear state, and
  per primitive its name, matrix, colour and (only when it differs from what the
  browser holds) its geometry — is assembled in Haskell into a `DrawBatch` and
  encoded as one JSON payload. `renderScene` is then a single call.
- **The browser replays it.** `batchExecutorSource` installs a small executor that
  owns the GL objects — program, uniform locations, per-primitive buffers — and
  replays the batch in the order it is given. It is deliberately thin: it knows
  nothing about ships, trajectories or the scene graph, and the GLSL still lives in
  Haskell and is passed to it at init.
- **`DrawBatch.hs` is the wire format.** Pure, browser-free, and the only place
  that knows how a frame is spelled: non-finite scalars become `0` so one bad
  coordinate cannot cost the whole frame, and text is escaped.
- **The upload cache stays in Haskell.** Geometry is still uploaded only when it
  differs, so a redraw of an unchanged scene carries matrices and colours only; the
  browser keys its buffers by primitive name and remembers the index count each
  upload set.
- **A failing frame does not end the session.** The executor catches its own errors
  and reports them through `console.error`. An exception crossing back into the
  widget kills that page's session while the process stays up, which is a failure
  mode already documented in [testing-and-tooling.md](../agents/testing-and-tooling.md),
  and a rendering bug must not be able to trigger it.

`preserveDrawingBuffer: true` was measured as an alternative and rejected as the
fix: it stops the boats vanishing (0% of the session boat-less with the flag forced
onto the same client) but leaves a frame's primitives split across presented frames,
so a half-drawn frame is still shown, and it leaves the round-trip cost in place.

## Consequences

- **Frames are atomic.** Against the same harness (idle 8 s, pointer 10 s, 348
  renders), a render's GL calls now span at most 0.3 ms (median 0.1 ms, was max
  19.2 ms), no render is split across presented frames (was 1–4 per run), and the
  canvas showed its boats for 100.0% of 26.1 s (was 95.0%).
- **The round-trip count per frame is now one.** A frame costs one call plus one
  websocket payload of 5.9 KiB per pointer move, most of it matrices; geometry still
  travels only when it changes.
- **The main-thread budget is still unmet, and it is no longer the render's.**
  `cdp-mainthread-cost.mjs` measures 7.84 ms of task and 11.09 blocking sync POSTs
  per pointer move, against a 2 ms / 2 POST budget. [Issue
  09](../../.scratch/mouse-navigation-trajectory-planner/issues/09-reduce-remaining-pointer-move-render-cost.md)
  recorded 13.37 ms and 140.5 KiB on the previous revision, but in another
  environment, so that is not a like-for-like fall; what this change removes is the
  render's share of the round trips, not the pointer path's, which is where the
  remaining cost is.
- **The renderer now has two halves in two languages.** The wire format is the seam:
  a change to the payload has to be made in `DrawBatch.hs` and `batchExecutorSource`
  together, and nothing type-checks that pairing — it failed exactly that way once
  while this was being written, with an executor that threw on every frame and a
  client that silently drew nothing. The gate has to be able to tell "nothing was
  drawn" apart from "everything was drawn correctly", which is why
  `cdp-canvas-flicker.mjs` treats too little evidence as a setup failure rather than
  a pass, and why `cdp-canvas-picture.mjs` exists to look at the result.
- **The geometry cache key is still the primitive name.** A node whose geometry
  changes without its name changing still re-uploads; a node reused for genuinely
  different geometry must compare unequal, which `Geometry3D` does.
- Remaining headroom, measured but not done: pointer-driven renders are still not
  coalesced to one per animation frame, so a 120–1000 Hz mouse still renders per
  event, and the speed-ring geometry still tracks ship speed rather than scaling a
  unit ring by the transform.
