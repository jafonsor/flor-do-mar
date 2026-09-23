Status: ready-for-agent

# Reduce Remaining Pointer-Move Render Cost

## What to build

The battle view no longer blocks the main thread for a whole frame per pointer move
(see [ADR-0005](../../../docs/adr/0005-client-render-and-input-wiring.md)), but two
measured costs remain and neither is fixed.

Current state against `.scratch/diagnosis/cdp-mainthread-cost.mjs` (120 moves at
60 Hz): **13.37 ms** of main-thread task per move, most of a 60 Hz frame;
**140.5 KiB** of websocket traffic per move; 11.3 blocking sync POSTs per move.

Two changes, in expected-value order:

1. **Coalesce pointer-driven renders to one per animation frame.** Renders are still
   driven by `updated battleSceneDynamic`, so the render rate equals the pointer
   event rate. The 60 Hz harness cannot show this by construction — it paces input at
   one event per frame — but a real mouse at 120–1000 Hz still produces a full render
   per event. This is remediation item 2 from the original diagnosis and is the
   larger win on real hardware.
2. **Scale the speed rings with the transform instead of rebuilding them.** A ring's
   radius tracks ship speed, so its geometry changes continuously and is re-uploaded
   on every render. Rendering a unit ring and scaling it via the world matrix would
   upload it once ever, and is probably the bulk of the remaining 140.5 KiB.

Do not chase jsaddle's list marshalling: `JS.val` on a list is already a single
`NewArray` command (`JavaScript.Array.Internal.fromListIO` -> `newArray`), so the
remaining bytes are real payload rather than per-element command overhead.

## Acceptance criteria

- [ ] Main-thread task per pointer move is under 2 ms, measured by
      `cdp-mainthread-cost.mjs`, which currently fails this budget.
- [ ] Blocking sync POSTs per pointer move are 2 or fewer.
- [ ] Speed-ring geometry is uploaded once rather than per render, or a measurement
      shows it was not the dominant remaining cost.
- [ ] `combat-test`, `diagnosis-divergence`, and `diagnosis-hover-perf` still pass.
- [ ] `cdp-pointer-behaviour.mjs` still reports 7/7: clicks issue orders, opposite
      canvas sides give opposite bearings, hover and mouseleave leave a committed
      order alone, drag works.

## Notes

The reported freeze was a separate defect — a browser tab that outlived a client
restart — and is documented in
[docs/agents/testing-and-tooling.md](../../../docs/agents/testing-and-tooling.md).
Reload the tab after restarting the client, or a stale-session crash will be
mistaken for a regression in this work.

`cdp-mainthread-cost.mjs` needs a client on `http://localhost:3911/` and headless
Chrome on CDP port 9224 with the SwiftShader flags; see the same doc.
