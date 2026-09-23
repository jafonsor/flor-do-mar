// Closely reproduce the reported freeze: a page left running while the player
// fires both broadsides in quick succession, as the screenshots show (tick 31
// with both sides reloading, then frozen at tick 54).
//
// This drives a *fresh* page against whatever server is on APP_URL, hammers both
// fire buttons like an impatient player, and samples:
//   * the app's own tick counter (is the session still being driven?)
//   * how long a trivial Runtime.evaluate takes (is the main thread stalled?)
//   * page console output and JS exceptions
//
// A freeze shows up as Runtime.evaluate timing out or the tick series flattening
// while the sample loop itself keeps running.
//
// Usage: node cdp-fire-storm.mjs [seconds]
// Exit:  0 = no freeze, 1 = freeze reproduced, 2 = setup failure.

const APP_URL = process.env.APP_URL || 'http://localhost:3912/';
const DURATION_SECONDS = Number(process.argv[2] || 90);
const log = (...a) => console.log(new Date().toISOString().slice(11, 23), ...a);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

class Cdp {
  constructor(ws) {
    this.ws = ws;
    this.nextId = 1;
    this.pending = new Map();
    this.events = [];
    ws.onmessage = (ev) => {
      let m;
      try {
        m = JSON.parse(typeof ev.data === 'string' ? ev.data : '');
      } catch {
        return;
      }
      if (m.method) this.events.push(m);
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
  close() {
    try {
      this.ws.close();
    } catch {}
  }
}

const READ_TICK = `(() => {
  const text = document.body ? document.body.innerText : '';
  const ti = text.indexOf('Tick ');
  if (ti < 0) return -1;
  let digits = '';
  for (let j = ti + 5; j < text.length; j++) {
    const c = text[j];
    if (c >= '0' && c <= '9') digits += c;
    else break;
  }
  return digits ? Number(digits) : -1;
})()`;

const CLICK = (label) => `(() => {
  const b = Array.from(document.querySelectorAll('button')).find((x) => x.textContent.trim() === ${JSON.stringify(label)});
  if (!b) return false;
  b.click();
  return true;
})()`;

const version = await (await fetch('http://127.0.0.1:9224/json/version')).json();
const browser = await Cdp.connect(version.webSocketDebuggerUrl);
const created = await browser.send('Target.createTarget', { url: 'about:blank' }, undefined, 8000);
const sid = (
  await browser.send('Target.attachToTarget', { targetId: created.result.targetId, flatten: true }, undefined, 8000)
).result.sessionId;
const S = (m, p, t) => browser.send(m, p, sid, t);

const pageProblems = [];
browser.events = browser.events || [];
const originalOnMessage = browser.ws.onmessage;
browser.ws.onmessage = (ev) => {
  originalOnMessage(ev);
  const last = browser.events[browser.events.length - 1];
  if (last?.method === 'Runtime.exceptionThrown') {
    pageProblems.push(`exception: ${last.params?.exceptionDetails?.text}`);
  }
  if (last?.method === 'Log.entryAdded' && last.params?.entry?.level === 'error') {
    pageProblems.push(`console: ${last.params.entry.text}`);
  }
};

await S('Page.enable');
await S('Runtime.enable');
await S('Log.enable');
await S('Page.navigate', { url: APP_URL }, 8000);

const evaluate = async (expression, timeoutMs = 5000) =>
  (await S('Runtime.evaluate', { expression, returnByValue: true }, timeoutMs)).result?.result?.value;

let ready = false;
for (let i = 0; i < 40 && !ready; i++) {
  await sleep(500);
  try {
    ready = (await evaluate(`Boolean(document.querySelector('canvas'))`)) === true;
  } catch {}
}
if (!ready) {
  log('SETUP FAIL: canvas never appeared');
  process.exit(2);
}
log(`loaded against ${APP_URL}`);

// Sample continuously. A stalled main thread shows up as a rising evaluate cost
// or a timeout; a dead session shows up as a frozen tick with a healthy main
// thread. Recording both separates the two failure modes.
let lastTick = await evaluate(READ_TICK);
const samples = [];
let evaluateTimeouts = 0;
const started = Date.now();
let fireFlip = false;

while ((Date.now() - started) / 1000 < DURATION_SECONDS) {
  await sleep(1000);
  const t0 = Date.now();
  let tick = null;
  try {
    tick = await evaluate(READ_TICK, 4000);
  } catch {
    evaluateTimeouts += 1;
  }
  const cost = Date.now() - t0;

  // Fire both sides on alternate seconds, the way an impatient player does.
  fireFlip = !fireFlip;
  try {
    await evaluate(CLICK(fireFlip ? 'Fire port' : 'Fire starboard'), 4000);
  } catch {
    evaluateTimeouts += 1;
  }

  samples.push({ tick, cost });
  const elapsed = Math.round((Date.now() - started) / 1000);
  if (tick !== null && tick !== lastTick) lastTick = tick;
  if (elapsed % 10 === 0) {
    log(`t=${elapsed}s tick=${tick} evaluate=${cost}ms timeouts=${evaluateTimeouts}`);
  }
}

const ticks = samples.map((s) => s.tick).filter((t) => typeof t === 'number' && t >= 0);
const maxCost = Math.max(...samples.map((s) => s.cost));
const stalled = samples.some((s) => s.tick === null);
const advancing = ticks.length >= 2 && ticks[ticks.length - 1] > ticks[0];

log(`\nsamples=${samples.length} ticks=${ticks[0]}..${ticks[ticks.length - 1]} maxEvaluate=${maxCost}ms timeouts=${evaluateTimeouts}`);
log(`page problems: ${pageProblems.length === 0 ? 'none' : JSON.stringify(pageProblems.slice(0, 10))}`);

const failures = [];
if (stalled || evaluateTimeouts > 0) failures.push('page main thread stopped answering');
if (!advancing) failures.push('tick counter stopped advancing');
if (pageProblems.some((p) => p.startsWith('exception'))) failures.push('page threw a JS exception');

if (failures.length > 0) {
  log(`FREEZE REPRODUCED: ${failures.join('; ')}`);
  browser.close();
  process.exit(1);
}
log('NO FREEZE: page kept ticking and answering for the whole run');
browser.close();
process.exit(0);
