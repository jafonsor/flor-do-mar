// Feedback loop for "the boats flicker in and out" (the battle canvas shows the
// trajectory strokes and speed rings with no ship hulls in them).
//
// It observes the ONE thing that can make a drawn scene disappear: a render is
// not one browser task. Every WebGL call the client makes is a jsaddle-warp
// round trip, so a single `renderScene` becomes dozens of separate tasks, and the
// compositor presents whatever is in the canvas when its own frame comes up. A
// canvas created without preserveDrawingBuffer is cleared once it has been
// presented, so the primitives drawn before that boundary are gone from every
// later frame: the head of the draw list (the ship hulls and their heading
// markers) is exactly what goes missing, which is the reported symptom.
//
// Method, all inside the real page:
//   * patch WebGLRenderingContext to record every `clear` and every
//     `drawElements` with its timestamp, index count and vertex count (recovered
//     from the bound ARRAY_BUFFER's byteLength);
//   * run a self-scheduling requestAnimationFrame loop to record the compositor's
//     frame boundaries;
//   * reconstruct each presented frame as "the draws since the previous frame
//     boundary" and ask whether it contains the ship meshes.
//
// The ships are the first six draws of a render (hull, heading marker and target
// marker, for two ships) and are the only unit-cube geometry in the scene, so
// "vertex count 8" identifies them exactly.
//
// Usage: node cdp-canvas-flicker.mjs [idleSeconds] [moveSeconds] [--preserve]
//   --preserve forces `preserveDrawingBuffer: true` onto the app's getContext
//   call from the browser side (no rebuild, no client restart). Under that flag
//   a presented canvas is NOT cleared, so the expected repair is that frames stop
//   losing the boats and only a full clear can ever be caught on screen.
// Assumes: the client is listening on 3911 and Chrome serves CDP on 9224.
// Exit:  0 = every presented frame had its ships, 1 = at least one did not (red),
//        2 = setup failure.

const argv = process.argv.slice(2);
const PRESERVE = argv.includes('--preserve');
const positional = argv.filter((a) => !a.startsWith('--'));
const IDLE_S = Number(positional[0] || 4);
const MOVE_S = Number(positional[1] || 8);

const APP_URL = 'http://localhost:3911/';
const log = (...a) => console.log(new Date().toISOString().slice(11, 23), ...a);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

class Cdp {
  constructor(ws) {
    this.ws = ws;
    this.nextId = 1;
    this.pending = new Map();
    ws.onmessage = (ev) => {
      let m;
      try {
        m = JSON.parse(typeof ev.data === 'string' ? ev.data : '');
      } catch {
        return;
      }
      if (m.id && this.pending.has(m.id)) {
        const { resolve, timer } = this.pending.get(m.id);
        this.pending.delete(m.id);
        clearTimeout(timer);
        resolve(m);
      }
    };
  }
  static async connect(url) {
    const ws = new WebSocket(url);
    await new Promise((resolve, reject) => {
      ws.onopen = resolve;
      ws.onerror = () => reject(new Error('ws fail'));
    });
    return new Cdp(ws);
  }
  send(method, params = {}, sessionId, timeoutMs = 15000) {
    const id = this.nextId++;
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(id);
        const e = new Error(`TIMEOUT ${method}`);
        e.timedOut = true;
        reject(e);
      }, timeoutMs);
      this.pending.set(id, { resolve, timer });
      const msg = { id, method, params };
      if (sessionId) msg.sessionId = sessionId;
      this.ws.send(JSON.stringify(msg));
    });
  }
}

// Installed before the app boots, so no client call escapes it.
const GL_PROBE = `
(function () {
  var entry = { t0: performance.now(), draws: [], clears: [], frames: [], uploads: 0, errors: [] };
  window.__gl = entry;
  var consoleError = console.error;
  console.error = function () {
    try { entry.errors.push(Array.prototype.join.call(arguments, ' ')); } catch (ignored) {}
    return consoleError.apply(console, arguments);
  };
  if (!window.WebGLRenderingContext) { entry.error = 'no WebGLRenderingContext'; return; }
  var P = WebGLRenderingContext.prototype;
  var bytes = new WeakMap();
  var boundArrayBuffer = null;
  var color = null;
  var bindBuffer = P.bindBuffer;
  P.bindBuffer = function (target, buffer) {
    if (target === 34962) boundArrayBuffer = buffer;
    return bindBuffer.apply(this, arguments);
  };
  var bufferData = P.bufferData;
  P.bufferData = function (target, data, usage) {
    if (target === 34962 && boundArrayBuffer && data && typeof data.byteLength === 'number') {
      bytes.set(boundArrayBuffer, data.byteLength);
      entry.uploads++;
    }
    return bufferData.apply(this, arguments);
  };
  var uniform4f = P.uniform4f;
  P.uniform4f = function (location, r, g, b, a) {
    color = [r, g, b, a];
    return uniform4f.apply(this, arguments);
  };
  var drawElements = P.drawElements;
  P.drawElements = function (mode, count, type, offset) {
    var size = boundArrayBuffer ? bytes.get(boundArrayBuffer) : undefined;
    entry.draws.push({
      t: performance.now(),
      indices: count,
      vertices: size === undefined ? -1 : size / 12,
      color: color
    });
    return drawElements.apply(this, arguments);
  };
  var clear = P.clear;
  P.clear = function (mask) {
    entry.clears.push(performance.now());
    return clear.apply(this, arguments);
  };
  var raf = window.requestAnimationFrame.bind(window);
  var lastTick = null;
  entry.ticks = [];
  (function loop() {
    var now = performance.now();
    entry.frames.push(now);
    var scenario = document.querySelector('.scenario');
    if (scenario) {
      var text = scenario.innerText;
      if (text !== lastTick) {
        lastTick = text;
        entry.ticks.push({ t: now, text: text });
      }
    }
    raf(loop);
  })();
})();
`;

const version = await (await fetch('http://127.0.0.1:9224/json/version')).json();
const browser = await Cdp.connect(version.webSocketDebuggerUrl);
const created = await browser.send('Target.createTarget', { url: 'about:blank' }, undefined, 8000);
const sid = (
  await browser.send('Target.attachToTarget', { targetId: created.result.targetId, flatten: true }, undefined, 8000)
).result.sessionId;
const S = (m, p, t) => browser.send(m, p, sid, t);
await S('Page.enable');
await S('Runtime.enable');
await S('Page.addScriptToEvaluateOnNewDocument', { source: GL_PROBE });
if (PRESERVE) {
  // Diagnostic override: pretend the client asked for a preserved drawing buffer.
  // With it, presenting a frame no longer clears the canvas, so the primitives
  // drawn before the boundary survive into later frames.
  await S('Page.addScriptToEvaluateOnNewDocument', {
    source: `
      (function () {
        var original = HTMLCanvasElement.prototype.getContext;
        HTMLCanvasElement.prototype.getContext = function (type, attributes) {
          if (type === 'webgl' || type === 'experimental-webgl') {
            attributes = Object.assign({}, attributes || {}, { preserveDrawingBuffer: true });
          }
          return original.call(this, type, attributes);
        };
      })();
    `,
  });
}
await S('Page.navigate', { url: APP_URL }, 8000);

const evaluate = async (expression) => {
  const r = await S('Runtime.evaluate', { expression, returnByValue: true }, 8000);
  return r.result?.result?.value;
};

// Every page this harness opens holds a WebGL context, and Chrome stops handing
// them out once enough pages are alive. Close our own target on the way out, in
// every path, so repeated runs cannot poison the next one.
async function closeTarget() {
  try {
    await browser.send('Target.closeTarget', { targetId: created.result.targetId }, undefined, 5000);
  } catch {
    /* the page is going away anyway */
  }
}

const canvasRect = async () => {
  const v = await evaluate(
    `(() => { const c = document.querySelector('canvas'); if (!c) return null; const r = c.getBoundingClientRect(); return {x:r.x,y:r.y,w:r.width,h:r.height}; })()`,
  );
  return v && v.w > 0 ? v : null;
};

let rect = null;
for (let i = 0; i < 40; i++) {
  await sleep(500);
  rect = await canvasRect();
  if (rect) break;
}
if (!rect) {
  log('SETUP FAIL: no canvas');
  await closeTarget();
  process.exit(2);
}
log(`canvas ${Math.round(rect.w)}x${Math.round(rect.h)}`);
await sleep(2000); // let the page settle and draw its first frames

// A page that never draws cannot judge anything, and it happens for reasons that
// have nothing to do with this defect: Chrome refuses a WebGL context once enough
// pages hold one, and the app reports exactly that on the console.
const health = async () => {
  const raw = await evaluate('JSON.stringify({ draws: window.__gl ? window.__gl.draws.length : -1, errors: window.__gl ? window.__gl.errors : [] })');
  return JSON.parse(raw || '{}');
};
const booted = await health();
if (booted.draws < 1) {
  log(`SETUP FAIL: the page drew nothing (${booted.draws} draws)`);
  for (const message of booted.errors.slice(0, 5)) log(`  console.error: ${message}`);
  log('  is the client on 3911 the one serving this page, and is Chrome short of WebGL contexts?');
  await closeTarget();
  process.exit(2);
}

// Mark the joins between phases in the page's own timeline.
const mark = async (label) => {
  await evaluate(`(window.__gl.marks = window.__gl.marks || []).push([${JSON.stringify(label)}, performance.now()])`);
  log(`phase: ${label}`);
};

const tickText = () => evaluate(`document.querySelector('.scenario').innerText`);

await mark('idle');
// Baseline: how fast does the simulation actually tick with no input at all?
const tickStart = Date.now();
const firstTick = await tickText();
await sleep(IDLE_S * 1000);
const lastTick = await tickText();

await mark('pointer');
const moves = Math.round((MOVE_S * 1000) / 32);
const moveStart = Date.now();
for (let i = 0; i < moves; i++) {
  const u = (i % 60) / 59;
  const v = 0.5 + 0.35 * Math.sin((i / 37) * Math.PI);
  try {
    await S('Input.dispatchMouseEvent', {
      type: 'mouseMoved',
      x: Math.round(rect.x + rect.w * (0.05 + 0.9 * u)),
      y: Math.round(rect.y + rect.h * (0.08 + 0.84 * v)),
      button: 'none',
      buttons: 0,
    });
  } catch {
    /* a stalled page is a result, not a crash */
  }
  await sleep(32);
}
const moveMs = Date.now() - moveStart;
await sleep(600);
await mark('end');

const tickEnd = await tickText();
const raw = await evaluate('JSON.stringify(window.__gl)');
if (!raw) {
  log('SETUP FAIL: no GL log (probe did not install?)');
  process.exit(2);
}
const gl = JSON.parse(raw);

// ---- what the compositor would have presented -------------------------------
// A frame boundary at t presents the draws issued since the previous boundary:
// presenting a canvas without preserveDrawingBuffer clears it.
const SHIP_VERTICES = 8;

const draws = gl.draws;
const clears = gl.clears;
const frames = gl.frames;

// Group draws into renders, one per clear: within a render the first six draws
// are the two ships' hull / heading / target markers.
let renderIndex = -1;
let drawIndexInRender = 0;
let clearCursor = 0;
for (const d of draws) {
  while (clearCursor < clears.length && clears[clearCursor] <= d.t) {
    renderIndex++;
    drawIndexInRender = 0;
    clearCursor++;
  }
  d.render = renderIndex;
  d.ordinal = drawIndexInRender++;
  d.ship = drawIndexInRender <= 6 && d.vertices === SHIP_VERTICES;
}
const renderStarts = clears.map((t, i) => ({ t, i, draws: 0, shipDraws: 0, overlayDraws: 0 }));
for (const d of draws) {
  const r = renderStarts[d.render];
  if (!r) continue;
  r.draws++;
  if (d.ship) r.shipDraws++;
  else r.overlayDraws++;
}

const presented = [];
for (let i = 1; i < frames.length; i++) {
  const from = frames[i - 1];
  const to = frames[i];
  const inWindow = draws.filter((d) => d.t > from && d.t <= to);
  if (inWindow.length === 0) continue; // nothing new drawn: no new frame presented
  // Without a preserved drawing buffer, presenting clears the canvas, so a frame
  // shows only what was drawn since the previous boundary. With one, nothing is
  // cleared, so a frame also carries whatever the current render has drawn so far
  // (a prefix of the draw list since that render's clear).
  const sinceClear = draws.filter((d) => d.t <= to && d.t > (clears[d.render] ?? -Infinity));
  const counted = PRESERVE ? sinceClear : inWindow;
  const ships = counted.filter((d) => d.ship).length;
  presented.push({
    t: to,
    ships,
    overlays: counted.length - ships,
    drawnNow: inWindow.length,
    renders: new Set(inWindow.map((d) => d.render)).size,
  });
}

const shipStats = new Map();
for (const d of draws) {
  const key = `${d.vertices}v ${d.ship ? 'SHIP' : 'overlay'}`;
  shipStats.set(key, (shipStats.get(key) || 0) + 1);
}

// A frame stays on screen until the next one is presented, so dwell time — not
// frame count — is what the player actually experiences as a flicker.
const lastFrame = presented.length ? presented[presented.length - 1].t : 0;
let boatsVisibleMs = 0;
let boatsHiddenMs = 0;
for (let i = 0; i < presented.length; i++) {
  const dwell = (i + 1 < presented.length ? presented[i + 1].t : lastFrame) - presented[i].t;
  if (presented[i].ships > 0) boatsVisibleMs += dwell;
  else boatsHiddenMs += dwell;
}
const observedMs = boatsVisibleMs + boatsHiddenMs;

// A render is torn when its own primitives were split across presented frames:
// the first presented frame holds the head of the draw list (the ships), the
// next holds the tail (the overlays) because presenting cleared the buffer.
let tornRenders = 0;
let example = null;
for (const r of renderStarts) {
  const after = presented.filter((f) => f.t > r.t);
  if (after.length < 2) continue;
  const head = after[0];
  const tail = after[1];
  if (head.ships > 0 && head.overlays > 0 && tail.ships === 0 && tail.overlays > 0) {
    tornRenders++;
    if (!example) example = { r, head, tail };
  }
}

const tickOf = (text) => Number((/(\d+)/.exec(text || '') || [])[1]);
const framesWithShips = presented.filter((f) => f.ships > 0).length;
const boatsMissing = presented.filter((f) => f.ships === 0);
const boatsMissingWithOverlays = boatsMissing.filter((f) => f.overlays > 0);
const primitivesPerRender = renderStarts.map((r) => r.draws);
const median = (xs) => (xs.length ? [...xs].sort((a, b) => a - b)[Math.floor(xs.length / 2)] : 0);

// How long a render takes the browser: the gap between its clear and its last
// draw is main-thread time spent inside jsaddle round trips.
const renderDurations = renderStarts.map((r) => {
  const own = draws.filter((d) => d.render === r.i);
  return own.length ? own[own.length - 1].t - r.t : 0;
});
const sessionMs = (frames.length ? frames[frames.length - 1] : 0) - (frames.length ? frames[0] : 0);
const renderBusyMs = renderDurations.reduce((a, b) => a + b, 0);
// Where a tick lands relative to the animation frame clock: 0 means the tick
// fired from inside a frame callback, a large offset means a timer.
const tickOffsets = (gl.ticks || []).slice(1).map((k) => {
  let best = Infinity;
  for (const f of frames) best = Math.min(best, Math.abs(f - k.t));
  return best;
});

log('');
log('================ RESULT ================');
log(`drawing buffer     : ${PRESERVE ? 'preserveDrawingBuffer: true (forced by the harness)' : 'default (a presented canvas is cleared)'}`);
log(`sim state          : ${firstTick}  ->  ${lastTick}`);
log(`tick rate          : idle ${((tickOf(lastTick) - tickOf(firstTick)) / (IDLE_S + 2)).toFixed(2)}/s` +
    ` (config tick_seconds = 0.8), pointer phase ${((tickOf(tickEnd) - tickOf(lastTick)) / (moveMs / 1000)).toFixed(2)}/s`);
log(`animation frames   : ${frames.length} in ${sessionMs.toFixed(0)}ms (${((frames.length / sessionMs) * 1000).toFixed(1)}/s)`);
log(`tick vs frame clock: median offset ${median(tickOffsets).toFixed(2)}ms (0 = tick fires inside a frame callback)`);
log('');
log(`renders observed   : ${renderStarts.length}  (primitives each: median ${median(primitivesPerRender)}, max ${Math.max(0, ...primitivesPerRender)})`);
log(`render duration    : median ${median(renderDurations).toFixed(1)}ms, max ${Math.max(0, ...renderDurations).toFixed(1)}ms` +
    `, ${renderBusyMs.toFixed(0)}ms of ${sessionMs.toFixed(0)}ms in a render (${((renderBusyMs / sessionMs) * 100).toFixed(0)}%)`);
log(`geometry uploads   : ${gl.uploads} bufferData calls for ${draws.length} draws`);
log(`ship draws         : ${draws.filter((d) => d.ship).length} (= 6 per render: hull, heading, target marker x2 ships)`);
log('');
log(`presented frames   : ${presented.length}`);
log(`  with ship draws  : ${framesWithShips}`);
log(`  without ships    : ${boatsMissing.length}`);
log(`  of those, overlays present: ${boatsMissingWithOverlays.length}`);
log('');
const percentage = (part) => (observedMs > 0 ? `${((part / observedMs) * 100).toFixed(1)}%` : 'n/a');
log(`canvas showed boats: ${boatsVisibleMs.toFixed(0)}ms of ${observedMs.toFixed(0)}ms (${percentage(boatsVisibleMs)})`);
log(`canvas showed NONE : ${boatsHiddenMs.toFixed(0)}ms of ${observedMs.toFixed(0)}ms (${percentage(boatsHiddenMs)})  <-- the flicker`);
log(`renders split across two presented frames: ${tornRenders} of ${renderStarts.length}`);
log('');

if (example) {
  const { r, head, tail } = example;
  log(`example torn render: clear at t=${r.t.toFixed(1)}ms, ${r.draws} primitives`);
  log(`  frame t=${head.t.toFixed(1)}ms presented head: ${head.ships} ship + ${head.overlays} overlay draws  (boats on screen)`);
  log(`  frame t=${tail.t.toFixed(1)}ms presented tail: ${tail.ships} ship + ${tail.overlays} overlay draws  (boats gone)`);
  log(`  the tail stayed on screen for ${(presented[presented.indexOf(tail) + 1]?.t - tail.t || 0).toFixed(0)}ms`);
  log('');
}
if (boatsMissing.length) {
  log('frames presented without ships (first 12):');
  for (const f of boatsMissing.slice(0, 12)) {
    log(`  t=${f.t.toFixed(1)}ms  ships=${f.ships} overlays=${f.overlays} renders=${f.renders}`);
  }
  log('');
}
// A verdict needs something to judge: a page that drew almost nothing, or a run
// whose pointer phase was starved, must not read as a pass.
if (renderStarts.length < 10 || presented.length < 10) {
  log(`SETUP FAIL: too little evidence to judge — ${renderStarts.length} renders, ${presented.length} presented frames.`);
  await closeTarget();
  process.exit(2);
}
if (boatsHiddenMs > 0) {
  log('RESULT: RED — the canvas reached the screen without its boats.');
  await closeTarget();
  process.exit(1);
}
log('RESULT: GREEN — every presented frame contained the ships.');
await closeTarget();
process.exit(0);
