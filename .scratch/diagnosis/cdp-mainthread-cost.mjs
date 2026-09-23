// Feedback loop for "the app freezes when I hover".
//
// The user-visible symptom is the browser main thread being blocked by pointer
// input. This measures exactly that, and nothing else:
//
//   * `TaskDuration` delta from Chrome's own metrics = main-thread time spent
//     servicing the input, per pointer move. A 16.7ms frame budget is the scale.
//   * synchronous `/sync/` POST count = jsaddle-warp round trips that block the
//     main thread by construction (the XHR is opened with async=false).
//   * long tasks (>50ms) = individual freezes the user would feel.
//
// It drives the REAL app in a REAL browser with REAL input events. No mocks.
//
// Usage: node cdp-mainthread-cost.mjs [moves] [stepMs]
// Exit:  0 = within budget, 1 = over budget (red), 2 = setup failure.

const MOVES = Number(process.argv[2] || 120);
const STEP_MS = Number(process.argv[3] || 16); // ~60 Hz, what a real mouse does

// Budgets. A pointer move must not consume anything like a whole frame.
const BUDGET_TASK_MS_PER_MOVE = 2.0;
const BUDGET_SYNC_PER_MOVE = 2.0;

const APP_URL = 'http://localhost:3911/';
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
      if (m.id && this.pending.has(m.id)) {
        const { resolve, timer } = this.pending.get(m.id);
        this.pending.delete(m.id);
        clearTimeout(timer);
        resolve(m);
        return;
      }
      if (m.method) this.events.push(m);
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

const METRIC_NAMES = [
  'TaskDuration',
  'ScriptDuration',
  'LayoutDuration',
  'RecalcStyleDuration',
];

const version = await (await fetch('http://127.0.0.1:9224/json/version')).json();
const browser = await Cdp.connect(version.webSocketDebuggerUrl);
const created = await browser.send('Target.createTarget', { url: 'about:blank' }, undefined, 8000);
const sid = (
  await browser.send('Target.attachToTarget', { targetId: created.result.targetId, flatten: true }, undefined, 8000)
).result.sessionId;
const S = (m, p, t) => browser.send(m, p, sid, t);
await S('Page.enable');
await S('Runtime.enable');
await S('Network.enable');
await S('Performance.enable');

// Install a long-task observer before the app boots.
await S('Page.addScriptToEvaluateOnNewDocument', {
  source: `
    window.__longTasks = [];
    try {
      new PerformanceObserver((list) => {
        for (const e of list.getEntries()) window.__longTasks.push({ start: e.startTime, dur: e.duration });
      }).observe({ entryTypes: ['longtask'] });
    } catch (err) { window.__longTaskError = String(err); }
  `,
});

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
log(`target ${created.result.targetId}, canvas ${rect.w}x${rect.h}`);
await sleep(1500); // let the app settle before measuring

const readMetrics = async () => {
  const r = await S('Performance.getMetrics');
  const out = {};
  for (const m of r.result?.metrics || []) if (METRIC_NAMES.includes(m.name)) out[m.name] = m.value;
  return out;
};

const tickText = async () =>
  (await S('Runtime.evaluate', { expression: `document.body.innerText.split('\\n')[0].slice(0,80)`, returnByValue: true }))
    .result?.result?.value;

const before = await readMetrics();
const baselineMoves = browser.events.length;
log(`before: ${JSON.stringify(before)}`);
log(`state : ${await tickText()}`);

const wallStart = Date.now();
let failed = 0;
for (let i = 0; i < MOVES; i++) {
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
    failed++;
  }
  await sleep(STEP_MS);
}
const wallMs = Date.now() - wallStart;

const after = await readMetrics();
const tickAfter = await tickText();
const longTasks = (
  await S('Runtime.evaluate', { expression: 'JSON.stringify(window.__longTasks || [])', returnByValue: true })
).result?.result?.value;
const lt = JSON.parse(longTasks || '[]');

const newEvents = browser.events.slice(baselineMoves);
const syncReqs = newEvents.filter(
  (e) => e.method === 'Network.requestWillBeSent' && e.params.request.url.includes('/sync/'),
);
const wsFrames = newEvents.filter((e) => e.method === 'Network.webSocketFrameReceived').length;
const wsBytes = newEvents
  .filter((e) => e.method === 'Network.webSocketFrameReceived')
  .reduce((n, e) => n + (e.params.response.payloadData?.length || 0), 0);

const d = (k) => (after[k] ?? 0) - (before[k] ?? 0);
const per = (k) => (d(k) * 1000) / MOVES; // Chrome reports seconds

log('');
log('================ RESULT ================');
log(`moves dispatched   : ${MOVES} (${failed} failed) over ${wallMs}ms wall`);
log(`state              : ${tickAfter}`);
log('');
log(`main-thread task   : ${(d('TaskDuration') * 1000).toFixed(1)}ms total, ${per('TaskDuration').toFixed(2)}ms per move`);
log(`  of which script  : ${(d('ScriptDuration') * 1000).toFixed(1)}ms total, ${per('ScriptDuration').toFixed(2)}ms per move`);
log(`  layout           : ${(d('LayoutDuration') * 1000).toFixed(1)}ms total, ${per('LayoutDuration').toFixed(2)}ms per move`);
log(`  recalc style     : ${(d('RecalcStyleDuration') * 1000).toFixed(1)}ms total, ${per('RecalcStyleDuration').toFixed(2)}ms per move`);
log('');
log(`blocking sync POSTs: ${syncReqs.length} total, ${(syncReqs.length / MOVES).toFixed(2)} per move`);
log(`ws frames received : ${wsFrames} total, ${(wsFrames / MOVES).toFixed(1)} per move`);
log(`ws bytes received  : ${(wsBytes / 1024).toFixed(1)} KiB total, ${(wsBytes / 1024 / MOVES).toFixed(1)} KiB per move`);
log(`long tasks (>50ms) : ${lt.length}${lt.length ? `, worst ${Math.max(...lt.map((t) => t.dur)).toFixed(0)}ms, total ${lt.reduce((n, t) => n + t.dur, 0).toFixed(0)}ms` : ''}`);
log('');
log(`budget             : task <= ${BUDGET_TASK_MS_PER_MOVE}ms/move, sync <= ${BUDGET_SYNC_PER_MOVE}/move`);

const taskPer = per('TaskDuration');
const syncPer = syncReqs.length / MOVES;
const over = taskPer > BUDGET_TASK_MS_PER_MOVE || syncPer > BUDGET_SYNC_PER_MOVE;

if (over) {
  log('');
  log(`RESULT: OVER BUDGET`);
  if (taskPer > BUDGET_TASK_MS_PER_MOVE) log(`  main-thread task ${taskPer.toFixed(2)}ms/move exceeds ${BUDGET_TASK_MS_PER_MOVE}ms`);
  if (syncPer > BUDGET_SYNC_PER_MOVE) log(`  ${syncPer.toFixed(2)} blocking sync POSTs per move exceeds ${BUDGET_SYNC_PER_MOVE}`);
  if (lt.length) log(`  ${lt.length} long task(s): the user feels these as freezes`);
  process.exit(1);
}
log('');
log('RESULT: within budget');
process.exit(0);
