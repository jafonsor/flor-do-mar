// Test the hypothesis that the freeze is a live page outliving its client
// process, not anything to do with firing.
//
// A page's jsaddle session lives in the server process. If that process is
// replaced, the page keeps its DOM but every callback it posts is answered with
// "jsaddle missing sync message handler", and the simulation — which only
// advances when the page posts a tick — stops dead. The page looks frozen while
// its main thread stays perfectly healthy.
//
// This script drives a page against APP_URL, samples the tick counter and the
// main-thread cost, then restarts the client mid-run via RESTART_CMD and
// samples again. The control is the same page and the same sampling; the only
// variable is the restart.
//
// Usage: RESTART_CMD='...' node cdp-stale-session.mjs
// Exit:  0 = session survived, 1 = stale-session freeze reproduced, 2 = setup failure.

const APP_URL = process.env.APP_URL || 'http://localhost:3913/';
const RESTART_CMD = process.env.RESTART_CMD;
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
  close() {
    try {
      this.ws.close();
    } catch {}
  }
}

const READ_STATE = `(() => {
  const text = document.body ? document.body.innerText : '';
  const ti = text.indexOf('Tick ');
  let digits = '';
  for (let j = ti + 5; ti >= 0 && j < text.length; j++) {
    const c = text[j];
    if (c >= '0' && c <= '9') digits += c;
    else break;
  }
  return { status: text.slice(0, 80).replace(/\\n/g, ' '), tick: digits ? Number(digits) : -1 };
})()`;

const version = await (await fetch('http://127.0.0.1:9224/json/version')).json();
const browser = await Cdp.connect(version.webSocketDebuggerUrl);
const created = await browser.send('Target.createTarget', { url: 'about:blank' }, undefined, 8000);
const sid = (
  await browser.send('Target.attachToTarget', { targetId: created.result.targetId, flatten: true }, undefined, 8000)
).result.sessionId;
const S = (m, p, t) => browser.send(m, p, sid, t);

const consoleLines = [];
const baseOnMessage = browser.ws.onmessage;
browser.ws.onmessage = (ev) => {
  baseOnMessage(ev);
  try {
    const m = JSON.parse(typeof ev.data === 'string' ? ev.data : '');
    if (m.method === 'Log.entryAdded' && m.params?.entry?.level === 'error') consoleLines.push(m.params.entry.text);
    if (m.method === 'Runtime.exceptionThrown') consoleLines.push('EXCEPTION ' + m.params?.exceptionDetails?.text);
  } catch {}
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

async function series(seconds, label) {
  const ticks = [];
  let maxCost = 0;
  let timeouts = 0;
  for (let i = 0; i < seconds; i++) {
    await sleep(1000);
    const t0 = Date.now();
    try {
      const state = await evaluate(READ_STATE, 4000);
      ticks.push(state?.tick ?? null);
    } catch {
      timeouts += 1;
      ticks.push('TIMEOUT');
    }
    maxCost = Math.max(maxCost, Date.now() - t0);
  }
  const state = await evaluate(READ_STATE, 4000).catch(() => null);
  log(`${label}: ticks=${ticks.join(',')} maxCost=${maxCost}ms timeouts=${timeouts} status="${state?.status ?? '?'}"`);
  return { ticks: ticks.filter((t) => typeof t === 'number'), timeouts, state };
}

const before = await series(6, 'before restart');
const advancedBefore = before.ticks.length >= 2 && before.ticks[before.ticks.length - 1] > before.ticks[0];
log(`page advances before restart: ${advancedBefore}`);

if (RESTART_CMD) {
  log(`restarting client: ${RESTART_CMD}`);
  const { execSync } = await import('node:child_process');
  try {
    execSync(RESTART_CMD, { stdio: 'inherit', shell: true });
  } catch (error) {
    log(`restart command failed: ${error.message}`);
  }
  await sleep(4000);
}

const after = await series(10, 'after restart');
const advancedAfter = after.ticks.length >= 2 && after.ticks[after.ticks.length - 1] > after.ticks[0];

log(`\npage problems: ${consoleLines.length === 0 ? 'none' : JSON.stringify([...new Set(consoleLines)].slice(0, 6))}`);
log(`advanced before=${advancedBefore} after=${advancedAfter} mainThreadTimeouts=${after.timeouts}`);

if (advancedBefore && !advancedAfter && after.timeouts === 0) {
  log('STALE-SESSION FREEZE REPRODUCED: DOM alive, simulation dead, no JS exception');
  browser.close();
  process.exit(1);
}
log('no stale-session freeze observed');
browser.close();
process.exit(0);
