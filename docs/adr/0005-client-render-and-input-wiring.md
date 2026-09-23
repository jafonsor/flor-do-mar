# ADR-0005: One Round Trip And One Upload Per Change In The Battle View

Status: Accepted

Date: 2026-09-23

## Context

The battle view froze under the pointer. It was not a geometry or planner bug —
`scan-hover-positions` sweeps 528,800 hover combinations with no exception and no
non-finite coordinate, and the cost per pointer move is flat across the canvas
(31–51 ms at 25 sampled positions, a 1.63x spread, against 0.03 ms with no input).
The cost was per *event* and uniform, and it came from the wiring between the
browser, jsaddle, and the renderer.

Three properties of that wiring compounded:

1. **jsaddle-warp transports a callback synchronously.** The browser issues the
   sync request with `XMLHttpRequest` opened `async=false`
   (`jsaddle-warp` `WebSockets.hs:231`), so the main thread blocks until the server
   answers. Every DOM property read from Haskell is therefore a blocking round
   trip, and `pointerIntentFromPointerEvent` read seven of them —
   `getBoundingClientRect`, `left`, `top`, `width`, `height`, `clientX`, `clientY` —
   per pointer event. `button` added an eighth on mousedown.
2. **The whole scene was re-uploaded on every render.** `renderScene` called
   `uploadGeometry` per primitive per frame, marshalling every vertex and index
   through jsaddle. A single 48-segment speed ring is roughly 900 values.
3. **There is no frame batching.** Renders are driven by
   `updated battleSceneDynamic`, which includes the hover waypoint, so the render
   rate equalled the pointer event rate.

Measured on the shipped config with real input at 60 Hz: **49.96 ms of main-thread
task per pointer move**, of which 47.35 ms was script; 17.7 blocking sync POSTs per
move; 774.8 KiB of websocket traffic per move; and 27 long tasks over 50 ms, worst
286 ms. A 286 ms stall is a freeze the player feels.

## Decision

Spend a round trip only when something actually changed, and upload geometry only
when it actually differs.

- **`BattleView.hs`** — the browser computes the pointer coordinate and passes plain
  numbers to the callback, so an event costs one round trip instead of eight. The
  primary-button test moved into JavaScript for the same reason. Coordinate
  arithmetic is unchanged; only *where* it runs moved.
- **`Renderer.hs`** — geometry is cached per primitive and compared before upload,
  so redrawing an unchanged scene costs nothing. Primitives own their buffers, so
  `vertexAttribPointer` is re-issued per primitive because it records whichever
  buffer is bound at the time.
- **`Main.hs`** — unrelated to rendering, but found in the same investigation: Warp
  is pinned to `127.0.0.1` so a duplicate client fails loudly instead of silently
  taking the other address family on port 3911.

## Consequences

- Main-thread task per pointer move fell **49.96 ms -> 13.37 ms**, websocket traffic
  **774.8 KiB -> 140.5 KiB**, and long tasks **27 (worst 286 ms) -> 1 (worst 71 ms)**
  against the same harness. Planner behaviour is untouched.
- **The number of blocking round trips is now the budget.** Anything that reads DOM
  state from Haskell on an input path re-introduces this class of stall. Prefer
  computing in the browser and passing values; if a value must be read from Haskell,
  read it once and cache it rather than per event.
- **The renderer holds mutable cache state.** `Renderer` carries an `IORef` of
  per-primitive geometry, so it is no longer a pure value and redraw correctness
  depends on the cache key identifying the geometry. Keys are the scene node names;
  a node whose geometry changes without its name changing still re-uploads, and a
  node reused for genuinely different geometry must compare unequal (it does —
  `Geometry3D` derives `Eq`).
- **Reuse is per primitive, not per frame.** Static parts of the scene — ship bodies,
  heading markers, rings — are uploaded once and rebound thereafter. Growing the
  per-frame upload cost means growing the number of primitives that *change* per
  frame.
- Remaining headroom, measured but not done: pointer-driven renders are still not
  coalesced to one per animation frame, so a 120–1000 Hz mouse still renders per
  event; and speed-ring geometry tracks ship speed, so it changes continuously and
  re-uploads every render. Scaling a unit ring by the transform matrix instead would
  upload it once. Tracked as
  `.scratch/mouse-navigation-trajectory-planner/issues/09-reduce-remaining-pointer-move-render-cost.md`.
- This work is **not** the fix for the reported freeze. That was a stale browser
  session across a client restart, documented in
  [testing-and-tooling.md](../agents/testing-and-tooling.md).
