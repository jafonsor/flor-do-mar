// Identify which request the page makes that the server answers 403, and what
// the page's state is at that moment. This is the missing link between "page
// looks frozen" and "jsaddle missing sync message handler".
//
// Usage: APP_URL=http://localhost:3912/ node cdp-network-log.mjs [seconds]
// Exit: 0 always (diagnostic).

const APP_URL = process.env.APP_URL || 'http://localhost:3912/';
const SECONDS = Number(process.argv[2] || 30);
const log = (...a) => console.log(new Date().toISOString().slice(11, 23), ...a);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

class Cdp {
  constructor(ws) {
    this.ws = ws;
    this.nextId = 1;
    this.pending = new Map();
    this.onEvent = () => {};
    ws.onmessage = (ev) => {
      let m;
      try {
        m = JSON.parse(typeof ev.data === 'string' ? ev.data : '');
      } catch {
        return;
      }
      if (m.method) this.onEvent(m);
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
  return { status: text.slice(0, 60).replace(/\\n/g, ' '), tick: digits ? Number(digits) : -1 };
})()`;

const version = await (await fetch('http://127.0.0.1:9224/json/version')).json();
const browser = await Cdp.connect(version.webSocketDebuggerUrl);
const created = await browser.send('Target.createTarget', { url: 'about:blank' }, undefined, 8000);
const sid = (
  await browser.send('Target.attachToTarget', { targetId: created.result.targetId, flatten: true }, undefined, 8000)
).result.sessionId;
const S = (m, p, t) => browser.send(m, p, sid, t);

const requests = new Map();
const interesting = [];
browser.onEvent = (m) => {
  if (m.method === 'Network.requestWillBeSent') {
    requests.set(m.params.requestId, m.params.request.url);
  }
  if (m.method === 'Network.responseReceived') {
    const url = requests.get(m.params.requestId) || m.params.response.url;
    const status = m.params.response.status;
    if (status >= 400 || !url.endsWith('/')) interesting.push({ url, status, at: Date.now() });
  }
  if (m.method === 'Log.entryAdded' && m.params?.entry?.level === 'error') {
    interesting.push({ log: m.params.entry.text, url: m.params.entry.url, at: Date.now() });
  }
  if (m.method === 'Runtime.exceptionThrown') {
    interesting.push({ exception: m.params?.exceptionDetails?.text, at: Date.now() });
  }
};

await S('Network.enable');
await S('Page.enable');
await S('Runtime.enable');
await S('Log.enable');

const evaluate = async (expression, timeoutMs = 5000) =>
  (await S('Runtime.evaluate', { expression, returnByValue: true }, timeoutMs)).result?.result?.value;

await S('Page.navigate', { url: APP_URL }, 8000);
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

const first = await evaluate(READ_STATE);
log(`loaded: ${JSON.stringify(first)}`);
const start = Date.now();
const tickHistory = [];
while ((Date.now() - start) / 1000 < SECONDS) {
  await sleep(1000);
  const state = await evaluate(READ_STATE).catch(() => null);
  const elapsed = Math.round((Date.now() - start) / 1000);
  tickHistory.push({ elapsed, tick: state?.tick, status: state?.status });
  const bad = interesting.filter((i) => i.at > Date.now() - 1100);
  if (bad.length > 0) log(`t=${elapsed}s state=${JSON.stringify(state)} problems=${JSON.stringify(bad)}`);
}

const ticks = tickHistory.map((h) => h.tick).filter((t) => typeof t === 'number' && t >= 0);
log(`\ntick series: ${ticks[0]}..${ticks[ticks.length - 1]} over ${SECONDS}s`);
log(`final status: ${tickHistory[tickHistory.length - 1]?.status}`);
log(`distinct problems: ${JSON.stringify([...new Set(interesting.map((i) => i.log || i.exception || `${i.status} ${i.url}`))], null, 2)}`);
browser.close();
process.exit(0);
