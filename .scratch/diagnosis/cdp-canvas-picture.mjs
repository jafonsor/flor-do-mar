// Capture what the battle canvas actually shows, as a PNG.
//
// `Page.captureScreenshot` does not reliably capture a WebGL canvas (see
// docs/agents/testing-and-tooling.md), so this asks the canvas itself. With
// `preserveDrawingBuffer` off, the drawing buffer is only readable inside the
// task that drew it, so the capture is taken from a microtask queued by the
// first `drawElements` of a frame: microtasks run when that task ends, which is
// after the last primitive and before the compositor can present or clear
// anything. Draw order and geometry are not touched.
//
// Usage: node cdp-canvas-picture.mjs [outPath]
// Exit:  0 = a picture was written, 2 = setup failure.

import { writeFileSync } from 'node:fs';

const OUT = process.argv[2] || '.scratch/diagnosis/canvas-picture.png';

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
  send(method, params = {}, sessionId, timeoutMs = 10000) {
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

const CAPTURE_PROBE = `
(function () {
  var pending = false;
  var prototype = WebGLRenderingContext.prototype;
  var drawElements = prototype.drawElements;
  prototype.drawElements = function () {
    if (!pending) {
      pending = true;
      var canvas = this.canvas;
      Promise.resolve().then(function () {
        pending = false;
        try { window.__fdmPicture = canvas.toDataURL('image/png'); } catch (error) { window.__fdmPictureError = String(error); }
      });
    }
    return drawElements.apply(this, arguments);
  };
})();
`;

const version = await (await fetch('http://127.0.0.1:9224/json/version')).json();
const browser = await Cdp.connect(version.webSocketDebuggerUrl);
const created = await browser.send('Target.createTarget', { url: 'about:blank' });
const sid = (await browser.send('Target.attachToTarget', { targetId: created.result.targetId, flatten: true })).result.sessionId;
const S = (m, p, t) => browser.send(m, p, sid, t);
await S('Page.enable');
await S('Runtime.enable');
await S('Page.addScriptToEvaluateOnNewDocument', { source: CAPTURE_PROBE });
await S('Page.navigate', { url: 'http://localhost:3911/' });

const evaluate = async (expression) => (await S('Runtime.evaluate', { expression, returnByValue: true })).result?.result?.value;

let picture = null;
for (let i = 0; i < 40; i++) {
  await sleep(500);
  picture = await evaluate('window.__fdmPicture || null');
  if (picture) break;
  const failure = await evaluate('window.__fdmPictureError || null');
  if (failure) {
    console.log(`SETUP FAIL: ${failure}`);
    process.exit(2);
  }
}
if (!picture) {
  console.log('SETUP FAIL: no frame was drawn');
  process.exit(2);
}

const state = await evaluate(`document.querySelector('.scenario').innerText`);
writeFileSync(OUT, Buffer.from(picture.split(',')[1], 'base64'));
console.log(`${state} -> ${OUT}`);
await S('Target.closeTarget', { targetId: created.result.targetId });
process.exit(0);
