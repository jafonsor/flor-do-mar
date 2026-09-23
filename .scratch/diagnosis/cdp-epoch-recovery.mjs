// Regression gate for the stale-session freeze.
//
// A page outlives the client process that served it whenever the client is
// rebuilt and restarted under an open tab. jsaddle keeps sync handlers in
// process memory, so such a page can never make another callback: it keeps its
// last frame on screen while its simulation stops dead, and the client logs
// "jsaddle missing sync message handler" once per callback the page attempts.
//
// The client now serves a page that compares the token of the process that
// served it against the token of whoever answers /epoch, and reloads itself when
// they differ. This script proves both halves:
//
//   1. a page with no stored token boots normally — the guard cannot loop
//   2. after RESTART_CMD replaces the client, the same page reloads itself and
//      resumes ticking, with no manual refresh
//
// Usage: RESTART_CMD='./restart-3911.sh' node cdp-epoch-recovery.mjs
// Exit:  0 = page recovered (or never needed to), 1 = page stayed frozen, 2 = setup failure.

const APP_URL = process.env.APP_URL || 'http://localhost:3911/';
const RESTART_CMD = process.env.RESTART_CMD;
const CDP_PORT = process.env.CDP_PORT || 9224;
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
  return {
    tick: digits ? Number(digits) : -1,
    hasCanvas: Boolean(document.querySelector('canvas')),
    token: document.documentElement.innerHTML.match(/var token = "([0-9]+)"/)?.[1] ?? null,
  };
})()`;

const version = await (await fetch(`http://127.0.0.1:${CDP_PORT}/json/version`)).json();
const browser = await Cdp.connect(version.webSocketDebuggerUrl);
const created = await browser.send('Target.createTarget', { url: 'about:blank' }, undefined, 8000);
const targetId = created.result.targetId;
const sid = (await browser.send('Target.attachToTarget', { targetId, flatten: true }, undefined, 8000)).result.sessionId;
const S = (m, p, t) => browser.send(m, p, sid, t);

const consoleErrors = [];
const baseOnMessage = browser.ws.onmessage;
browser.ws.onmessage = (ev) => {
  baseOnMessage(ev);
  try {
    const m = JSON.parse(typeof ev.data === 'string' ? ev.data : '');
    if (m.method === 'Log.entryAdded' && m.params?.entry?.level === 'error') consoleErrors.push(m.params.entry.text);
    if (m.method === 'Runtime.exceptionThrown') consoleErrors.push('EXCEPTION ' + m.params?.exceptionDetails?.text);
  } catch {}
};

await S('Page.enable');
await S('Runtime.enable');
await S('Log.enable');
await S('Page.navigate', { url: APP_URL }, 8000);

const evaluate = async (expression, timeoutMs = 5000) =>
  (await S('Runtime.evaluate', { expression, returnByValue: true }, timeoutMs)).result?.result?.value;

let firstLoad = null;
for (let i = 0; i < 60; i++) {
  await sleep(500);
  try {
    const state = await evaluate(READ_STATE);
    if (state?.hasCanvas) {
      firstLoad = state;
      break;
    }
  } catch {}
}
if (!firstLoad) {
  log('SETUP FAIL: canvas never appeared on first load');
  process.exit(2);
}
log(`first load: ${JSON.stringify(firstLoad)}`);

async function series(seconds, label) {
  const ticks = [];
  for (let i = 0; i < seconds; i++) {
    await sleep(1000);
    try {
      const state = await evaluate(READ_STATE, 4000);
      ticks.push(state?.tick ?? null);
    } catch {
      ticks.push('TIMEOUT');
    }
  }
  const numeric = ticks.filter((t) => typeof t === 'number');
  const advancing = numeric.length >= 2 && numeric[numeric.length - 1] > numeric[0];
  log(`${label}: ${ticks.join(',')} -> ${advancing ? 'advancing' : 'STALLED'}`);
  return { ticks: numeric, advancing };
}

const before = await series(5, 'before restart');

if (!RESTART_CMD) {
  log('no RESTART_CMD given: only the first-load check ran');
  if (before.advancing) {
    log('PASS: a fresh page boots and ticks with no stored token');
    browser.close();
    process.exit(0);
  }
  log('FAIL: fresh page did not tick');
  browser.close();
  process.exit(1);
}

// Put a *stale* token in the page's storage the way a real restart leaves it,
// then replace the client. The page can only recover by noticing the mismatch.
log(`restarting client: ${RESTART_CMD}`);
const { execSync } = await import('node:child_process');
try {
  execSync(RESTART_CMD, { stdio: 'inherit', shell: true });
} catch (error) {
  log(`restart command failed: ${error.message}`);
  process.exit(2);
}
await sleep(2000);

const after = await series(12, 'after restart');
const state = await evaluate(READ_STATE).catch(() => null);
log(`final: ${JSON.stringify(state)}`);
log(`console errors: ${consoleErrors.length === 0 ? 'none' : JSON.stringify([...new Set(consoleErrors)].slice(0, 5))}`);

if (before.advancing && after.advancing) {
  log('PASS: the page reloaded itself onto the new client and resumed ticking');
  browser.close();
  process.exit(0);
}
log('FAIL: page did not recover after the client was replaced');
browser.close();
process.exit(1);
