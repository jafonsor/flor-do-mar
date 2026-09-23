// Verify the pointer path still behaves after replacing the per-property jsaddle
// reads with a single JS-side conversion.
//
// What the rewrite could plausibly have broken:
//   * the coordinate mapping (wrong axis, inverted, or a value that never arrives)
//   * the primary-button test, now done in JS
//   * mouseleave clearing the hover
//   * the callback wiring itself (a JS factory that never fires)
//
// The strong check is that clicking left and right of the ship produces roughly
// opposite target headings. Getting one click to "work" could survive an ignored
// coordinate; getting opposite bearings cannot.
//
// Usage: node cdp-pointer-behaviour.mjs
// Exit:  0 = behaves, 1 = regression, 2 = setup failure.

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
    await new Promise((res, rej) => {
      ws.onopen = res;
      ws.onerror = () => rej(new Error('ws fail'));
    });
    return new Cdp(ws);
  }
  send(method, params = {}, sessionId, timeoutMs = 15000) {
    const id = this.nextId++;
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(id);
        reject(new Error(`TIMEOUT ${method}`));
      }, timeoutMs);
      this.pending.set(id, { resolve, timer });
      const msg = { id, method, params };
      if (sessionId) msg.sessionId = sessionId;
      this.ws.send(JSON.stringify(msg));
    });
  }
}

// Read the per-ship lines the app renders. "Player" and "Enemy" label the panels.
// Backslashes are avoided entirely: escaping a regex through a template literal
// silently produced a non-matching pattern in an earlier harness.
const READ_STATE = `(() => {
  const text = document.body ? document.body.innerText : '';
  const num = (segment, label) => {
    const i = segment.indexOf(label);
    if (i < 0) return null;
    let digits = '';
    for (let j = i + label.length; j < segment.length; j++) {
      const c = segment[j];
      if ((c >= '0' && c <= '9') || c === '-' || c === '.') digits += c;
      else if (digits) break;
    }
    return digits && digits !== '-' ? Number(digits) : null;
  };
  const ti = text.indexOf('Tick ');
  let tickDigits = '';
  for (let j = ti + 5; ti >= 0 && j < text.length; j++) {
    const c = text[j];
    if (c >= '0' && c <= '9') tickDigits += c;
    else break;
  }
  const playerSeg = text.split('Player')[1] || '';
  const enemySeg = text.split('Enemy')[1] || '';
  return {
    tick: tickDigits ? Number(tickDigits) : null,
    playerHeading: num(playerSeg, 'Heading'),
    playerTarget: num(playerSeg, 'Target'),
    playerSpeed: num(playerSeg, 'Speed'),
    enemyHeading: num(enemySeg, 'Heading'),
  };
})()`;

const version = await (await fetch('http://127.0.0.1:9224/json/version')).json();
const browser = await Cdp.connect(version.webSocketDebuggerUrl);
const created = await browser.send('Target.createTarget', { url: 'about:blank' }, undefined, 8000);
const sid = (
  await browser.send('Target.attachToTarget', { targetId: created.result.targetId, flatten: true }, undefined, 8000)
).result.sessionId;
const S = (m, p, t) => browser.send(m, p, sid, t);
await S('Page.enable');
await S('Runtime.enable');
await S('Page.navigate', { url: APP_URL }, 8000);

const READ_RECT = `(() => { const c = document.querySelector('canvas'); if (!c) return null; const r = c.getBoundingClientRect(); return {x:r.x,y:r.y,w:r.width,h:r.height}; })()`;
let rect = null;
for (let i = 0; i < 40; i++) {
  await sleep(500);
  try {
    rect = (await S('Runtime.evaluate', { expression: READ_RECT, returnByValue: true })).result?.result?.value;
  } catch {}
  if (rect) break;
}
if (!rect) {
  log('SETUP FAIL: no canvas');
  process.exit(2);
}
await sleep(2000);
log(`canvas ${rect.w}x${rect.h} at (${rect.x},${rect.y})`);

const px = (u) => Math.round(rect.x + rect.w * u);
const py = (v) => Math.round(rect.y + rect.h * v);
const state = async () =>
  (await S('Runtime.evaluate', { expression: READ_STATE, returnByValue: true })).result?.result?.value;

const move = (u, v) =>
  S('Input.dispatchMouseEvent', { type: 'mouseMoved', x: px(u), y: py(v), button: 'none', buttons: 0 });
const press = (u, v) =>
  S('Input.dispatchMouseEvent', { type: 'mousePressed', x: px(u), y: py(v), button: 'left', buttons: 1, clickCount: 1 });
const release = (u, v) =>
  S('Input.dispatchMouseEvent', { type: 'mouseReleased', x: px(u), y: py(v), button: 'left', buttons: 0, clickCount: 1 });

const results = [];
const check = (name, ok, detail) => {
  results.push({ name, ok, detail });
  log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? `  [${detail}]` : ''}`);
};

const baseline = await state();
log(`baseline: ${JSON.stringify(baseline)}`);

// --- 1. A click issues an order: the ship gets a target heading and starts moving.
await move(0.9, 0.5);
await press(0.9, 0.5);
await release(0.9, 0.5);
await sleep(3000);
const afterRight = await state();
log(`after right click: ${JSON.stringify(afterRight)}`);
check(
  'click issues a navigation order',
  afterRight.playerTarget !== null && afterRight.playerTarget !== baseline.playerTarget,
  `target ${baseline.playerTarget} -> ${afterRight.playerTarget}`,
);
check(
  'ship starts moving after the order',
  afterRight.playerSpeed !== null && afterRight.playerSpeed > 0,
  `speed ${baseline.playerSpeed} -> ${afterRight.playerSpeed}`,
);

// --- 2. Clicking the opposite side gives a roughly opposite bearing.
await move(0.1, 0.5);
await press(0.1, 0.5);
await release(0.1, 0.5);
await sleep(3000);
const afterLeft = await state();
log(`after left click : ${JSON.stringify(afterLeft)}`);
const delta = (a, b) => {
  if (a === null || b === null) return null;
  let d = Math.abs(a - b) % 360;
  return d > 180 ? 360 - d : d;
};
const separation = delta(afterRight.playerTarget, afterLeft.playerTarget);
check(
  'opposite canvas sides give opposite bearings',
  separation !== null && separation > 120,
  `right target ${afterRight.playerTarget}, left target ${afterLeft.playerTarget}, separation ${separation?.toFixed(0)} deg`,
);

// --- 3. Hover across the whole canvas, then leave: no crash, sim keeps running.
for (let i = 0; i < 24; i++) {
  await move(0.05 + 0.9 * (i / 23), 0.15 + 0.7 * ((i % 7) / 6));
  await sleep(30);
}
const duringHover = await state();
await S('Input.dispatchMouseEvent', { type: 'mouseMoved', x: Math.round(rect.x - 60), y: Math.round(rect.y - 40), button: 'none', buttons: 0 });
await sleep(1500);
const afterLeave = await state();
log(`during hover: ${JSON.stringify(duringHover)}`);
log(`after leave : ${JSON.stringify(afterLeave)}`);
check(
  'simulation keeps ticking through hover and mouseleave',
  afterLeave.tick !== null && afterLeave.tick > baseline.tick,
  `tick ${baseline.tick} -> ${afterLeave.tick}`,
);
check(
  'hover does not re-issue the committed order',
  duringHover.playerTarget !== null &&
    afterLeft.playerTarget !== null &&
    Math.abs(duringHover.playerTarget - afterLeft.playerTarget) <= 10,
  `target ${afterLeft.playerTarget} -> ${duringHover.playerTarget} (bearing drifts as the ship moves toward a fixed waypoint)`,
);

// --- 4. Drag gesture (press, move out, release) still issues and survives.
await move(0.3, 0.6);
await press(0.3, 0.6);
for (let i = 1; i <= 10; i++) {
  await move(0.3 + 0.03 * i, 0.6 - 0.02 * i);
  await sleep(30);
}
await release(0.6, 0.4);
await sleep(2500);
const afterDrag = await state();
log(`after drag  : ${JSON.stringify(afterDrag)}`);
check(
  'drag gesture issues an order and the app survives',
  afterDrag.tick !== null && afterDrag.tick > afterLeave.tick && afterDrag.playerTarget !== null,
  `tick ${afterLeave.tick} -> ${afterDrag.tick}, target ${afterDrag.playerTarget}`,
);

// --- 5. Enemy still manoeuvres: the simulation is healthy, not stalled.
const headings = new Set();
for (let i = 0; i < 6; i++) {
  const s = await state();
  if (s.enemyHeading !== null) headings.add(Math.round(s.enemyHeading));
  await sleep(900);
}
check('enemy keeps manoeuvring', headings.size > 2, `${headings.size} distinct headings`);

const failed = results.filter((r) => !r.ok);
log('');
log('================ VERDICT ================');
log(`${results.length - failed.length}/${results.length} checks passed`);
if (failed.length) {
  failed.forEach((f) => log(`  FAILED: ${f.name} [${f.detail}]`));
  process.exit(1);
}
log('pointer behaviour intact');
process.exit(0);
