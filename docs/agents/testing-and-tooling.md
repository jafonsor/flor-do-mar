# Testing And Local Tooling

Traps that cost real time to find. Each one produced a *false* signal during the
movement work (see [ADR-0004](../../docs/adr/0004-arrival-tolerance-from-turning-circle.md)
and [ADR-0005](../../docs/adr/0005-client-render-and-input-wiring.md)), so they are
worth knowing before you debug.

## A browser tab that outlives the client used to freeze silently

**Fixed: the page now reloads itself onto the new client.** The trap is kept here
because its symptoms are easy to misread as a gameplay bug, and because the same
symptom has a second cause that is *not* fixed.

A tab that connected to a previous client process keeps a session id that only
existed in that process: jsaddle identifies a context by a `syncKey`, and
`syncHandlers` is a per-process `IORef`
(`jsaddle-warp` `WebSockets.hs:79`). Every callback the page makes is posted to
`/sync/<syncKey>`, so after a restart the new process hits
`Nothing -> error "jsaddle missing sync message handler"` (`WebSockets.hs:129`) on
every single one, and the page's synchronous XHR sees a failure it cannot recover
from.

What you see when nothing catches it:

- The page **looks** frozen but is not hung: its main thread answers in ~2 ms.
- The tick counter never advances. Nothing re-renders, because no callback reaches
  the app.
- The client log fills with `jsaddle missing sync message handler` — one per
  pointer move.

It masquerades as a **hover bug**: every pointer move issues sync requests, so
moving the mouse is merely *how you discover* the page was already dead. The
pointer position is not the variable. It also masquerades as **flakiness**, since
it depends only on whether the open tab predates the last restart — that is, on the
normal edit/rebuild/re-run loop.

`app/client/Main.hs` now closes it: the client serves its page with a per-process
token in a head script, and the page compares that token against whoever answers
`/epoch`. A mismatch means the process behind the page is gone, so it reloads. Two
details are load-bearing:

- The websocket upgrade is a `GET /` too, so the page handler must let
  `Upgrade: websocket` requests through untouched. Answering them with the page
  breaks jsaddle entirely — the browser just reports failed websocket connections.
- The token is stored in `localStorage` and compared before reloading, so a page
  that somehow keeps seeing a mismatch reloads once rather than looping.

`.scratch/diagnosis/cdp-epoch-recovery.mjs` is the gate: it drives a page, replaces
the client under it, and asserts the page resumes ticking with no manual refresh.

The second cause of the same symptom is **not** self-healing: a real exception
inside the widget kills that page's session while the process stays up, and the
page then looks exactly like the stale-session case. Before blaming a stale tab,
check whether the client logged an exception.

## Two clients can silently share port 3911

Warp's default host is `*`. On a dual-stack machine a second instance does **not**
fail to bind: the first instance holds one address family, so the second falls
through to the other and both end up listening on 3911. A duplicate client is
therefore silent, and the browser can reach either one.

This produces the same `missing sync message handler` error by a different route —
a page whose websocket lands on one process and whose sync request lands on the
other. `serverSettings` pins the host to `127.0.0.1` so a second instance fails
loudly with `address already in use`. If you ever see two `flor-do-mar-client`
processes in `lsof -nP -iTCP:3911`, that is this.

## A pure hover sweep cannot see client/server bugs

`scan-hover-positions` sweeps 6610 hover positions across 80 simulation states —
528,800 combinations — and traps both a Haskell exception and a non-finite
coordinate. It passes, and it was still pointed at the wrong layer: the freeze it
was written to find lives in the session lifecycle and the render loop, which a
pure Haskell seam cannot reach.

Sweeping more positions would never have found it. When a symptom resists a sweep,
suspect the seam rather than the sweep size. Assert on the user-visible symptom
(a tick that stops advancing, a main thread that stalls) somewhere that can
actually observe it.

## A half-drawn canvas is not a missing scene

The battle canvas sometimes showed the trajectory strokes and speed rings with no
ship hulls, heading markers or target markers in them. The obvious reading — the
snapshot or the scene lost its ships, so instrument the FRP graph — is wrong, and
so is the layer it points at.

The scene was always complete. Every render issued exactly six unit-cube draws
(measured: 1272 over 212 renders), and one flickering frame also drew the player's
*hover* overlay, which is derived from the player's own entry in the same snapshot:
a scene that had lost the player's ship could not have drawn it.

What was missing was the canvas, not the scene. `renderScene` issued one jsaddle
round trip per WebGL call, so a render was dozens of browser tasks and the
compositor could present the canvas between any two of them. A canvas created
without `preserveDrawingBuffer` is cleared once it has been presented, so whatever
had been drawn before that boundary was wiped — and the ships are the first six
primitives of the draw order, which is why they are the part that vanishes while
strokes and rings, drawn after the boundary, survive. Frames are atomic now
([ADR-0007](../../docs/adr/0007-one-browser-task-per-frame.md)); this is kept
because the symptom points confidently at the wrong layer.

`cdp-canvas-flicker.mjs` is the gate, and `--preserve` is the one-variable check:
forcing `preserveDrawingBuffer: true` from the browser side, with no rebuild and no
client restart, turned a session that spent 4.8% of its time with no boats on the
canvas into one that spent 0%:

```bash
node .scratch/diagnosis/cdp-canvas-flicker.mjs 6 6              # RED, 4.8% without boats
node .scratch/diagnosis/cdp-canvas-flicker.mjs 6 6 --preserve   # GREEN, 0%
```

Two habits follow:

- When something *drawn* is absent from the screen, ask what the canvas was told to
  draw before doubting what the scene contained. The draw calls are cheap to count;
  a scene is not cheap to doubt.
- A gate has to tell "nothing was drawn" apart from "everything was drawn
  correctly". The first green run of this harness had drawn zero frames — its
  executor threw on every render — because a page with no frames is also a page with
  no frame *missing* the boats. It now fails fast on a page that never drew, and
  refuses a verdict without evidence.

## Driving the client in a browser

The client is a native Haskell server on **port 3911** that drives the browser over
a websocket. To exercise it headlessly with Chrome DevTools Protocol:

```bash
cabal run -v0 flor-do-mar-client            # serves http://localhost:3911/
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
  --headless=new --remote-debugging-port=9224 \
  --user-data-dir=/tmp/chrome-diag --no-sandbox \
  --use-gl=angle --use-angle=swiftshader --enable-unsafe-swiftshader
```

Two traps, plus two sandbox notes:

- **Headless Chrome has no WebGL without the SwiftShader flags.** With plain
  `--disable-gpu`, `getContext('webgl')` returns null, the app logs
  `"Could not initialize battle renderer: WebGL context is unavailable."`, and the
  canvas stays blank. That is a Chrome limitation, not a rendering bug. The flags
  above give a working `webgl` context.
- **`Page.captureScreenshot` does not reliably capture a WebGL canvas**, and
  `gl.readPixels` after compositing returns an empty buffer. Prefer asserting on
  the app's own state text, which the client renders as
  `Tick N | <scenario> | Player | Hull … | Enemy | Hull … | Gunnery | …`.
  That text is the cheapest ground truth for "did the simulation actually progress".
  When the *pixels* are what is in question, `cdp-canvas-picture.mjs` captures them
  reliably by asking the canvas from a microtask queued inside the frame's own task
  — see *A half-drawn canvas is not a missing scene* above.
- **The repo-local `--user-data-dir` and `TMPDIR` workaround is not always enough
  (Chrome 153).** Redirecting both is the first thing to try, but Chrome still
  aborted with `Failed to create socket directory` /
  `Failed to create a ProcessSingleton for your profile directory`, and crashpad
  still logged `Operation not permitted` for
  `~/Library/Application Support/Google/Chrome/Crashpad/settings.dat`. With
  `TMPDIR` under `.scratch/diagnosis/`, under `dist-newstyle/`, and as short as
  `/tmp/fdm-tmp`, the failure was identical; the browser started only when the
  launch itself was escalated out of the workspace-only sandbox. Budget for that
  rather than re-deriving it — and re-check it on a Chrome upgrade, since it is
  pinned to one.
- **Every harness page holds a WebGL context, and Chrome stops handing them out.**
  A run that leaves its page open can starve the next one: that page gets no
  context, draws nothing, and any check that only asks "were the boats missing?"
  reads as a pass. Close your own target on every exit path (as
  `cdp-canvas-flicker.mjs` does) and use `cdp-close-pages.mjs` to clear up after a
  harness that does not.

Harnesses live in `.scratch/diagnosis/` and are worth reusing rather than
rewriting. All give every CDP command a hard deadline, so a stalled page is a
*result* rather than a hung script:

- `cdp-canvas-flicker.mjs` — the gate for the render path. Patches the page's
  `WebGLRenderingContext` before the app boots, records every `clear` and
  `drawElements` with its vertex count, and reconstructs what each presented frame
  contained. Red when a frame reaches the screen with strokes and rings but no ship
  hulls; `--preserve` forces `preserveDrawingBuffer: true` from the browser side,
  which is the one-variable check that the drawing buffer's post-present clear is
  what loses them. Run it after any change to the renderer or the render scene.
- `cdp-canvas-picture.mjs` — writes what the canvas actually shows to
  `.scratch/diagnosis/canvas-picture.png`. Look at it after any change to the
  renderer: the flicker gate asserts the boats are *drawn*, not that the picture is
  right.
- `cdp-close-pages.mjs` — closes leftover pages on the client's URL, for the WebGL
  context limit above. Closing a page can, rarely, take the client process down —
  see the disconnect defect in
  [issue 01](../../.scratch/mesh-rendering-pipeline/issues/01-battle-canvas-frames-lose-the-boats.md).
- `cdp-mainthread-cost.mjs` — the regression gate for render cost. Drives real
  pointer input at 60 Hz and asserts on Chrome's own `TaskDuration` delta per move,
  blocking sync-POST count, and long tasks. Run it after any change to the battle
  view, the renderer, or the input path.
- `cdp-pointer-behaviour.mjs` — asserts the pointer path still behaves (a click
  issues an order, opposite canvas sides give opposite bearings, hover and
  mouseleave leave a committed order alone, drag works). Its last check, "enemy
  keeps manoeuvring", samples headings for 5.4 s and can fail on a long straight
  leg; confirm against a fresh page before calling it a regression.
- `cdp-epoch-recovery.mjs` — the gate for the stale-page fix. Drives a page,
  replaces the client under it via `restart-3911.sh`, and asserts the page reloads
  itself and resumes ticking. Run it after any change to how the page is served.
- `cdp-stale-session.mjs`, `cdp-fire-storm.mjs`, `cdp-fire-freeze.mjs` — the
  diagnosis harnesses for that freeze. The fire ones are controls: they showed
  that firing does *not* freeze a fresh page, which is what pointed the
  investigation at session lifetime instead.

Start the client as a job that outlives the command that launched it. A client
backgrounded from inside a tool call can be gone by the next one, and a dead client
looks exactly like a page that never booted.

## Planner tests that use their own yaw acceleration can hide a hunting controller

`test/CombatTest.hs` drives navigation against a hand-written
`navigationMovement` fixture (`yaw_acceleration = 180`), while the packaged
config ships `yaw_acceleration = 10`. A steering law that commands full rudder
authority for any heading error is a relay, and its overshoot after the heading
error changes sign is `yaw_rate^2 / (2 * yaw_acceleration)`: at 180 that is ~2.5
degrees and reads as "settles fine", at 10 it is ~45 degrees and visible as a
ship weaving left and right along its whole approach
([ADR-0006](../../docs/adr/0006-proportional-navigation-steering.md)).

Two habits follow:

- Tune and reproduce movement bugs against the **shipped** config
  (`loadRuntimeCombatConfig`), not a test fixture's physics.
- When a controller looks stable in tests but hunts in play, compare the
  fixture's inertia parameters with the runtime ones before suspecting the
  controller's math.

`test/DiagnosisTrajectoryShape.hs` exists for this: it runs one order against the
shipped config and asserts that steering holds one turn direction and that the
settled path runs straight at the waypoint. A pure "did it arrive" assertion
does not catch the weave — the old relay law still arrived, it just wandered
1.45x the direct distance on the way.

## Build without writing outside the workspace

Cabal logs to `~/.cache/cabal/logs/build.log`. Under a restricted sandbox that
write fails **after** compilation and linking succeed, so the build looks broken
when it is not. Point cabal at a repo-local directory instead:

```bash
CABAL_DIR="$PWD/.cabal-local" cabal build combat-test
```

`.cabal-local/` and `dist-newstyle/` are gitignored. `git` itself is not available
to restricted agents in this repo; if you cannot run it, hand the commit to the
user.

## Regression tests for navigation

Two dedicated executables exist, both asserting behaviour rather than mechanism:

- `cabal run diagnosis-divergence` — a plan terminates by arriving rather than
  exhausting the safety cap; a ship clears its order; the orbit autopilot advances
  through waypoints; the duel stays bounded.
- `cabal run diagnosis-hover-perf` — the planner converges, plans stay small, and
  per-hover cost stays under budget.

They are currently named `diagnosis-*` and live beside `test/CombatTest.hs`. If the
navigation work settles, they are worth promoting into `combat-test`.

Note that `diagnosis-hover-perf` includes a deliberate **guard** assertion on
planner cost. It passes today and exists so a future fix cannot make convergence
work by making the planner slow. It measures the *planner* only — client render cost
is what `cdp-mainthread-cost.mjs` is for.
