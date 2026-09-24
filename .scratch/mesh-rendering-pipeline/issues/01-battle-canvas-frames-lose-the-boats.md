Status: ready-for-agent

# Battle Canvas Frames Lose The Boats

## What is wrong

The battle canvas sometimes shows the trajectory strokes and the speed rings with
no ship hulls, heading markers or target markers in them. Reported from play with
five screenshots, which show the tick advancing while the boats come and go:

| screenshot time | tick | what the canvas showed |
| --- | --- | --- |
| 22:49:57 | 0 | both boats |
| 22:50:13 | 1 | no boats; the enemy's speed rings were drawn |
| 22:50:35 | 4 | both boats |
| 22:51:04 | 5 | no boats; enemy trajectory + rings and the player's hover overlay were drawn |
| 22:51:22 | 6 | both boats |

The player's hover overlay is the load-bearing detail: the hover plan is derived
from the player's own snapshot (`battleSceneHoverNavigationPlan`), so a frame that
draws it while the player's hull is missing proves the **scene was complete** and
the canvas lost primitives after they were drawn. The frame in question also
carries the enemy's trajectory and rings, which sit *after* the ships in
`battleRenderScene`'s draw order.

## Cause

A render is not one browser task. `renderScene` issues one jsaddle-warp round trip
per WebGL call — `viewport`, `clear*`, `useProgram`, and then per primitive
`bindBuffer` x2, `vertexAttribPointer`, `uniformMatrix4fv`, `uniform4f`,
`drawElements` — so the compositor can present the canvas between any two of them.
A canvas created without `preserveDrawingBuffer` is cleared once it has been
presented, so everything drawn before that boundary is wiped. The ships are the
first six primitives of every render (hull, heading marker, target marker, for two
ships), so they are the primitives that go missing whenever a boundary lands
mid-render; the strokes and rings drawn after it are what remains on screen.

This is not the FRP network. Every render issues exactly six unit-cube draws
(measured: 2070 ship draws over 345 renders), and the flickering frames' snapshots
demonstrably still contained the ships (see the hover overlay above).

## Reproduction

`.scratch/diagnosis/cdp-canvas-flicker.mjs` patches the page's
`WebGLRenderingContext` before the app boots, records every `clear` and
`drawElements` with a vertex count recovered from the bound `ARRAY_BUFFER`, and
reconstructs what each presented frame contained.

```bash
node .scratch/diagnosis/cdp-canvas-flicker.mjs 6 6
```

```
renders observed   : 212  (primitives each: median 12, max 12)
render duration    : median 0.2ms, max 19.2ms, 90ms of 18649ms in a render (0%)
geometry uploads   : 234 bufferData calls for 2508 draws
ship draws         : 1272 (= 6 per render: hull, heading, target marker x2 ships)

presented frames   : 204
  with ship draws  : 200
  without ships    : 4
  of those, overlays present: 4

canvas showed boats: 17491ms of 18377ms (95.2%)
canvas showed NONE : 886ms of 18377ms (4.8%)  <-- the flicker
renders split across two presented frames: 1 of 212

example torn render: clear at t=8541.4ms, 12 primitives
  frame t=8541.6ms presented head: 6 ship + 3 overlay draws  (boats on screen)
  frame t=8557.1ms presented tail: 0 ship + 3 overlay draws  (boats gone)
  the tail stayed on screen for 49ms
RESULT: RED — the canvas reached the screen without its boats.
```

Six runs give 4.7–5.1% of the session with no boats on the canvas. A boat-less
frame stays up until the next render, so its dwell time is bounded by whatever
drives renders — 49–784 ms in these runs (one idle tick period is 800 ms) and up
to the whole interval in a session whose ticks are slow (see below).

**One-variable proof.** Forcing `preserveDrawingBuffer: true` onto the app's
`getContext` call *from the browser side* — no rebuild, no client restart — turns
the same measurement green, because presenting no longer clears what was already
drawn:

```bash
node .scratch/diagnosis/cdp-canvas-flicker.mjs 6 6 --preserve
# presented frames: 212, without ships: 0
# canvas showed boats: 18400ms of 18400ms (100.0%)
# RESULT: GREEN — every presented frame contained the ships.
```

Same client, same 212 renders, same 1272 ship draws, same tick rate, no other
change.

## Open question: what drives the render rate

The reported session's tick spacing cannot be read off the screenshot file
timestamps — those are not evenly spaced and the captures were not taken at tick
moments — so nothing here depends on them. What does matter is that a boat-less
frame stays up until the next render, so anything that lowers the render rate
(fewer animation frames, a starved tick loop, an idle page with no pointer
activity) lengthens the time the boats are missing.

One stall *was* observed: a page whose tick counter stopped for 20 s while its
animation frames ran at 59.7/s and the widget issued no further renders. That is
the documented "an exception inside the widget kills the page's session" failure
mode ([testing-and-tooling.md](../../../docs/agents/testing-and-tooling.md)), not
this defect — it froze the ticks instead of the boats.

While reproducing this, the client process itself died twice, with an uncaught

```
flor-do-mar-client: Warp: Client closed connection prematurely
```

after browser pages were closed abruptly (`Target.closeTarget` on six live pages).
That is a separate defect: a client disconnect should not be able to take the
process down. It also means a session can vanish mid-play, which is worth chasing
on its own.

## Candidate fixes

1. **Execute a render's whole GL command stream in one browser task.** Keep the
   command list in Haskell, hand it to the page in a single call with objects
   (program, uniforms, buffers) referenced by handle, and let one JS function
   replay it. Presentation then happens at task boundaries only, so no composite
   can land inside a render. This also collapses the blocking sync POSTs per
   render to one, which is the second acceptance criterion of
   [issue 09](../../mouse-navigation-trajectory-planner/issues/09-reduce-remaining-pointer-move-render-cost.md).
2. **`preserveDrawingBuffer: true`** — proven above to remove the symptom, but it
   leaves the render torn (a prefix of the draw list can still be presented) and
   leaves the round-trip cost in place. A mitigation, not the fix.
3. **Fewer primitives per render** (e.g. skip heading markers, or fold the ring
   and stroke geometry together) — reduces the window in which a boundary can
   land, but cannot close it.

Whichever fix lands, `cdp-canvas-flicker.mjs` is the gate: it is red today and
must be green after.

## Comments

**Fix 1 implemented** ([ADR-0007](../../../docs/adr/0007-one-browser-task-per-frame.md)).
A frame is now assembled in Haskell into a `DrawBatch` (`DrawBatch.hs`, the pure
wire format), encoded as one JSON payload, and replayed by a thin browser-side
executor installed by `batchExecutorSource` in `Renderer.hs`. The browser owns the
GL objects; Haskell owns the scene, the geometry and the decision about what needs
uploading, which is unchanged.

Gate, same harness, final revision (idle 8 s, pointer 10 s):

```
renders observed   : 348  (primitives each: median 12, max 12)
render duration    : median 0.1ms, max 0.3ms, 23ms of 26789ms in a render (0%)
ship draws         : 2088 (= 6 per render: hull, heading, target marker x2 ships)
presented frames   : 330
  with ship draws  : 330
  without ships    : 0
canvas showed boats: 26123ms of 26123ms (100.0%)
canvas showed NONE : 0ms of 26123ms (0.0%)  <-- the flicker
renders split across two presented frames: 0 of 348
RESULT: GREEN — every presented frame contained the ships.
```

Before the change the same harness reported a render's GL calls spanning up to
19.2 ms, 1–4 torn renders per run, and 4.7–5.1% of the session with no boats.

Also checked on the same revision: `cdp-pointer-behaviour.mjs` 7/7,
`cdp-canvas-picture.mjs` writes the tick-0 scene with both boats and their heading
and target markers, and `cdp-mainthread-cost.mjs` measures 7.84 ms of main-thread
task and 11.09 blocking sync POSTs per pointer move — the 2 ms budget is still
unmet and belongs to the pointer path, not the render path, so issue 09 stays open.

Two harness lessons came out of this and are worth the docs (proposed, not yet
written): a gate must treat "observed nothing" as a setup failure rather than a
pass — the first green run after this change had drawn zero frames because the
executor threw on every render — and every harness page holds a WebGL context, so
a harness that leaves its page open can starve the next run of a context.
`cdp-canvas-flicker.mjs` now does both: it fails fast on a page that never drew,
requires evidence before a verdict, and closes its own target.
