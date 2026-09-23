// Reproduce the reported freeze: a page that ticks normally, then stops advancing
// shortly after the player fires a broadside, with the client logging
// "jsaddle missing sync message handler".
//
// What this asserts, in order:
//   1. a freshly loaded page advances its own tick counter
//   2. clicking "Fire port" is accepted (the panel reports the reload)
//   3. the tick counter keeps advancing afterwards
//   4. the page's main thread still answers Runtime.evaluate at the end
//
// A frozen tab fails 3 and/or 4. That distinction matters: the tick counter is
// app state driven by server callbacks, while Runtime.evaluate only proves the
// renderer process is alive. Comparing them separates "the app stopped being
// driven" from "the process died".
//
// Usage: node cdp-fire-freeze.mjs
// Exit:  0 = no freeze, 1 = freeze reproduced, 2 = setup failure.

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
  close() {
    try {
      this.ws.close();
    } catch {}
  }
}

// Backslashes are avoided in these expressions on purpose: escaping a regex
// through a template literal silently produced a non-matching pattern once.
const READ_STATE = `(() => {
  const text = document.body ? document.body.innerText : '';
  const ti = text.indexOf('Tick ');
  let tickDigits = '';
  for (let j = ti + 5; ti >= 0 && j < text.length; j++) {
    const c = text[j];
    if (c >= '0' && c <= '9') tickDigits += c;
    else break;
  }
  const playerSeg = text.split('Player')[1] || '';
  const pi = playerSeg.indexOf('Reload');
  let reloadDigits = '';
  for (let j = pi + 6; pi >= 0 && j < playerSeg.length; j++) {
    const c = playerSeg[j];
    if (c >= '0' && c <= '9') reloadDigits += c;
    else if (reloadDigits) break;
  }
  return {
    tick: tickDigits ? Number(tickDigits) : null,
    playerReload: reloadDigits ? Number(reloadDigits) : null,
    buttons: Array.from(document.querySelectorAll('button')).map((b) => b.textContent),
  };
})()`;

const CLICK_FIRE_PORT = `(() => {
  const b = Array.from(document.querySelectorAll('button')).find((x) => x.textContent.trim() === 'Fire port');
  if (!b) return false;
  b.click();
  return true;
})()`;

let browser;
let sessionId;
let S;

async function connect(port) {
  const version = await (await fetch(`http://127.0.0.1:${port}/json/version`)).json();
  browser = await Cdp.connect(version.webSocketDebuggerUrl);
  const created = await browser.send('Target.createTarget', { url: 'about:blank' }, undefined, 8000);
  sessionId = (
    await browser.send('Target.attachToTarget', { targetId: created.result.targetId, flatten: true }, undefined, 8000)
  ).result.sessionId;
  S = (m, p, t) => browser.send(m, p, sessionId, t);
  await S('Page.enable');
  await S('Runtime.enable');
  await S('Log.enable');
}

// Sample the tick counter every 500 ms and report the last few readings.
async function tickSeries(seconds, label) {
  const readings = [];
  for (let i = 0; i < seconds * 2; i++) {
    await sleep(500);
    try {
      const value = (await S('Runtime.evaluate', { expression: READ_STATE, returnByValue: true }, 5000)).result?.result?.value;
      readings.push(value ? value.tick : null);
    } catch (error) {
      readings.push(`ERR:${error.message}`);
    }
  }
  log(`${label}: ${readings.join(', ')}`);
  return readings;
}

const numeric = (readings) => readings.filter((r) => typeof r === 'number');
const advanced = (readings) => {
  const values = numeric(readings);
  return values.length >= 2 && values[values.length - 1] > values[0];
};

const results = [];
const check = (name, ok, detail) => {
  results.push({ name, ok, detail });
  log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? `  [${detail}]` : ''}`);
};

const port = Number(process.argv[2] || 9224);
try {
  await connect(port);
} catch (error) {
  log(`SETUP FAIL: cannot reach CDP on ${port}: ${error.message}`);
  process.exit(2);
}

await S('Page.navigate', { url: APP_URL }, 8000);

// Wait for the canvas, which only exists once Reflex has built the widget.
const READ_READY = `(() => Boolean(document.querySelector('canvas')))()`;
let ready = false;
for (let i = 0; i < 40; i++) {
  await sleep(500);
  try {
    ready = (await S('Runtime.evaluate', { expression: READ_READY, returnByValue: true }, 5000)).result?.result?.value === true;
  } catch {}
  if (ready) break;
}
if (!ready) {
  log('SETUP FAIL: canvas never appeared');
  process.exit(2);
}
log('canvas ready');

const before = (await S('Runtime.evaluate', { expression: READ_STATE, returnByValue: true }, 5000)).result?.result?.value;
log(`loaded: ${JSON.stringify(before)}`);

const baseline = await tickSeries(4, 'before fire');
check('page advances its tick counter before firing', advanced(baseline), `${numeric(baseline).join(' -> ')}`);

// Fire exactly the way the player does: a real click on the real button.
const clicked = (await S('Runtime.evaluate', { expression: CLICK_FIRE_PORT, returnByValue: true }, 5000)).result?.result?.value;
check('Fire port button is present and clicked', clicked === true);

const afterFire = await tickSeries(8, 'after fire');
check('page keeps advancing its tick counter after firing', advanced(afterFire), `${numeric(afterFire).join(' -> ')}`);

const finalState = await S('Runtime.evaluate', { expression: READ_STATE, returnByValue: true }, 5000)
  .then((r) => r.result?.result?.value)
  .catch((error) => ({ error: error.message }));
log(`final: ${JSON.stringify(finalState)}`);
check('main thread still answers after firing', finalState !== undefined && finalState !== null && !finalState.error, JSON.stringify(finalState));

// A second and third shot exercise the reload path, which is what the reported
// freeze followed.
for (const shot of [2, 3]) {
  await sleep(3000);
  await S('Runtime.evaluate', { expression: CLICK_FIRE_PORT, returnByValue: true }, 5000).catch(() => {});
  const series = await tickSeries(4, `after shot ${shot}`);
  check(`page keeps advancing after shot ${shot}`, advanced(series), `${numeric(series).join(' -> ')}`);
}

const failures = results.filter((r) => !r.ok);
log(`\n${results.length - failures.length}/${results.length} checks passed`);
if (failures.length > 0) {
  for (const f of failures) log(`  FAILED: ${f.name}`);
  browser?.close();
  process.exit(1);
}
browser?.close();
process.exit(0);
