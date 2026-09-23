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

Two traps, plus one sandbox note:

- **Headless Chrome has no WebGL without the SwiftShader flags.** With plain
  `--disable-gpu`, `getContext('webgl')` returns null, the app logs
  `"Could not initialize battle renderer: WebGL context is unavailable."`, and the
  canvas stays blank. That is a Chrome limitation, not a rendering bug. The flags
  above give a working `webgl` context.
- **`Page.captureScreenshot` does not reliably capture a WebGL canvas**, and
  `gl.readPixels` after compositing returns an empty buffer. Prefer asserting on
  the app's own state text, which the client renders as
  `Tick N | <scenario> | Player | Hull … | Enemy | Hull … | Engagement | Range …`.
  That text is the cheapest ground truth for "did the simulation actually progress".
- **Under a restricted workspace sandbox, pass a repo-local `--user-data-dir` and
  `TMPDIR`.** Chromium refuses to start when it cannot create its
  process-singleton socket and crashpad directory, and it exits 21 with
  `Failed to create a ProcessSingleton for your profile directory` rather than
  anything that names the sandbox. Pointing both at `.scratch/diagnosis/` (or
  escalating) is what unblocks it.

Harnesses live in `.scratch/diagnosis/` and are worth reusing rather than
rewriting. All give every CDP command a hard deadline, so a stalled page is a
*result* rather than a hung script:

- `cdp-mainthread-cost.mjs` — the regression gate for render cost. Drives real
  pointer input at 60 Hz and asserts on Chrome's own `TaskDuration` delta per move,
  blocking sync-POST count, and long tasks. Run it after any change to the battle
  view, the renderer, or the input path.
- `cdp-pointer-behaviour.mjs` — asserts the pointer path still behaves (a click
  issues an order, opposite canvas sides give opposite bearings, hover and
  mouseleave leave a committed order alone, drag works).
- `cdp-epoch-recovery.mjs` — the gate for the stale-page fix. Drives a page,
  replaces the client under it via `restart-3911.sh`, and asserts the page reloads
  itself and resumes ticking. Run it after any change to how the page is served.
- `cdp-stale-session.mjs`, `cdp-fire-storm.mjs`, `cdp-fire-freeze.mjs` — the
  diagnosis harnesses for that freeze. The fire ones are controls: they showed
  that firing does *not* freeze a fresh page, which is what pointed the
  investigation at session lifetime instead.

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
