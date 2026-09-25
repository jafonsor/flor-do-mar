// Drive the shipped duel through the whole firing loop in a real browser, and
// capture what the canvas shows while an envelope is on screen.
//
// The pure suite proves the rules; this proves the *page*: that the gun panel is
// an overlay and not a wall, that a click on a hull locks it, that the toggle's
// colour is optimistic, that a volley leaves when the target comes into reach,
// that disengaging mid-reload stops the next one, and that the drawn envelope is
// legible at the shipped zoom.
//
// Usage: node cdp-firing-loop.mjs [outPath]
//   outPath defaults to .scratch/diagnosis/canvas-picture.png (gitignored).
// Assumes: the client is listening on 3911 and a browser serves CDP on 9224.
// Exit: 0 = the loop behaves and a picture was written, 1 = regression,
//       2 = setup failure.

import { writeFileSync } from 'node:fs';

const OUT = process.argv[2] || '.scratch/diagnosis/canvas-picture.png';
// A second frame, taken while the guns are loaded and nothing is in reach, so the
// wedge is the full envelope: the issue's "full and unhighlighted" case. It is a
// look-check artifact, so it lives outside the repo.
const LOADED_OUT = process.env.FIRING_LOOP_LOADED_OUT || '/tmp/flor-do-mar-loaded-wedge.png';
const APP_URL = process.env.APP_URL || 'http://localhost:3911/';
const CDP_URL = process.env.CDP_URL || 'http://127.0.0.1:9224';

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const log = (...a) => console.log(new Date().toISOString().slice(11, 23), ...a);

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

// Capture the canvas from a microtask queued by the first drawElements of a
// frame: the drawing buffer is only readable before the compositor presents it.
// Same mechanism as cdp-canvas-picture.mjs.
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

// The three status panels in DOM order: the player's, the enemy's, and the
// gunnery readout. Reading them by class beats splitting the whole body text.
const READ_PANELS = `(() => {
  const panels = [...document.querySelectorAll('.status-grid .panel')].map((p) => p.innerText);
  const toggle = document.querySelector('.fire-toggle');
  const lock = document.querySelector('.lock-control');
  const panel = document.querySelector('.gun-panel');
  const control = document.querySelector('.gun-panel .gun-control');
  return {
    player: panels[0] || '',
    enemy: panels[1] || '',
    gunnery: panels[2] || '',
    scenario: (document.querySelector('.scenario') || {}).innerText || '',
    toggleClass: toggle ? toggle.className : null,
    toggleDisabled: toggle ? toggle.disabled : null,
    lockVisible: lock ? getComputedStyle(lock).display !== 'none' : null,
    lockLabel: lock ? lock.innerText : null,
    hasReloadCircle: !!document.querySelector('.reload-circle'),
    panelPointerEvents: panel ? getComputedStyle(panel).pointerEvents : null,
    controlPointerEvents: control ? getComputedStyle(control).pointerEvents : null,
    picture: window.__fdmPicture || null,
    pictureError: window.__fdmPictureError || null,
  };
})()`;

const numberAfter = (text, label) => {
  const i = text.indexOf(label);
  if (i < 0) return null;
  let digits = '';
  for (let j = i + label.length; j < text.length; j++) {
    const c = text[j];
    if ((c >= '0' && c <= '9') || c === '-') digits += c;
    else if (digits) break;
  }
  return digits && digits !== '-' ? Number(digits) : null;
};

// "Player Locked Just EnemyShip, Fire at will True, Reload 3 of 3 | Enemy …"
// The lock reads as "none" when there is no target and "Just EnemyShip" when
// there is, so the target id is what the checks compare.
const gunneryFor = (text, who) => {
  const segment = (text.split('|').find((part) => part.includes(`${who} Locked`)) || '').trim();
  const locked = /Locked ([^,]+)/.exec(segment);
  const armed = /Fire at will (True|False)/.exec(segment);
  const reload = /Reload (\d+) of (\d+)/.exec(segment);
  const lockedText = locked ? locked[1].trim() : null;
  return {
    locked: lockedText === null || lockedText === 'none' ? null : lockedText.replace(/^Just\s+/, ''),
    armed: armed ? armed[1] === 'True' : null,
    reload: reload ? Number(reload[1]) : null,
    reloadTotal: reload ? Number(reload[2]) : null,
  };
};

const tickOf = (scenario) => {
  const match = /Tick (\d+)/.exec(scenario);
  return match ? Number(match[1]) : null;
};

const version = await (await fetch(`${CDP_URL}/json/version`)).json();
const browser = await Cdp.connect(version.webSocketDebuggerUrl);
const created = await browser.send('Target.createTarget', { url: 'about:blank' });
const sid = (
  await browser.send('Target.attachToTarget', { targetId: created.result.targetId, flatten: true })
).result.sessionId;
const S = (m, p, t) => browser.send(m, p, sid, t);
const evaluate = async (expression) =>
  (await S('Runtime.evaluate', { expression, returnByValue: true })).result?.result?.value;

await S('Page.enable');
await S('Runtime.enable');
await S('Page.addScriptToEvaluateOnNewDocument', { source: CAPTURE_PROBE });
await S('Page.navigate', { url: APP_URL });

let rect = null;
for (let i = 0; i < 40; i++) {
  await sleep(500);
  rect = await evaluate(
    `(() => { const c = document.querySelector('canvas'); if (!c) return null; const r = c.getBoundingClientRect(); return {x:r.x,y:r.y,w:r.width,h:r.height}; })()`,
  );
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
const state = () => evaluate(READ_PANELS);
const move = (u, v) =>
  S('Input.dispatchMouseEvent', { type: 'mouseMoved', x: px(u), y: py(v), button: 'none', buttons: 0 });
const press = (u, v) =>
  S('Input.dispatchMouseEvent', { type: 'mousePressed', x: px(u), y: py(v), button: 'left', buttons: 1, clickCount: 1 });
const release = (u, v) =>
  S('Input.dispatchMouseEvent', { type: 'mouseReleased', x: px(u), y: py(v), button: 'left', buttons: 0, clickCount: 1 });
const clickCanvas = async (u, v) => {
  await move(u, v);
  await press(u, v);
  await release(u, v);
};

const results = [];
const check = (name, ok, detail) => {
  results.push({ name, ok });
  log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? `  [${detail}]` : ''}`);
};

const boot = await state();
check(
  'the gun panel is present with a toggle, a lock control and a reload circle',
  boot.toggleClass !== null && boot.lockLabel !== null && boot.hasReloadCircle,
  `toggle=${boot.toggleClass} lock=${boot.lockLabel} circle=${boot.hasReloadCircle}`,
);
check(
  'the panel is an overlay: it passes pointer events through and only its controls capture them',
  boot.panelPointerEvents === 'none' && boot.controlPointerEvents === 'auto',
  `panel=${boot.panelPointerEvents} control=${boot.controlPointerEvents}`,
);
// The enemy locks on its own delay, which has elapsed by the time a page has
// drawn a few frames; the player's own state is the one that starts untouched.
check(
  'the player starts with no lock and no permission of its own',
  gunneryFor(boot.gunnery, 'Player').locked === null &&
    gunneryFor(boot.gunnery, 'Player').armed === false,
  boot.gunnery,
);

// --- Navigation still works with the panel over the canvas: a click on open
// water north of the player is a navigation order and re-aims the hull. It runs
// before the fight so the scenario is still running — a finished duel refuses
// navigation by design.
const before = await state();
await clickCanvas(0.5, 0.55);
await sleep(2500);
const turned = await state();
check(
  'a click on open water still issues a navigation order',
  numberAfter(turned.player, 'Target') !== null &&
    numberAfter(turned.player, 'Target') !== numberAfter(before.player, 'Target'),
  `target ${numberAfter(before.player, 'Target')} -> ${numberAfter(turned.player, 'Target')}`,
);

// --- Park the player beside the orbit so the enemy comes to it. A tiny drag from
// the player's own hull selects a near-zero post-waypoint speed, and a drag that
// starts on the player's own hull is a navigation order rather than a self-lock.
// The player started at world (0, 0), which is the canvas centre horizontally and
// 0.7667 down at the shipped camera; the click above moved it a little north, so
// the press lands a few pixels above that.
await press(0.5, 0.74);
await move(0.505, 0.74);
await release(0.505, 0.74);
await sleep(2500);
const parked = await state();
check(
  'a drag that started on the player hull navigated instead of locking',
  gunneryFor(parked.gunnery, 'Player').locked === null,
  parked.gunnery,
);

// --- Find the enemy by sweeping the reticle over its orbit, then click it. The
// orbit is x in [-24, 24], y in [16, 64] about (0, 40): u in [0.41, 0.59],
// v in [0.34, 0.66] at the shipped camera.
let hovered = null;
for (let row = 0; row <= 8 && !hovered; row++) {
  for (let column = 0; column <= 6 && !hovered; column++) {
    const u = 0.41 + (0.18 * column) / 6;
    const v = 0.34 + (0.32 * row) / 8;
    await move(u, v);
    await sleep(60);
    const probe = await state();
    if (probe.lockVisible) {
      hovered = { u, v, label: probe.lockLabel };
      break;
    }
  }
}
check('hovering an enemy hull offers a lock in the panel', hovered !== null, hovered ? `at u=${hovered.u.toFixed(2)} v=${hovered.v.toFixed(2)}` : 'never offered');

if (hovered) {
  await clickCanvas(hovered.u, hovered.v);
  await sleep(1800);
  const locked = await state();
  const player = gunneryFor(locked.gunnery, 'Player');
  check(
    'clicking the hovered enemy hull locks it',
    player.locked === 'EnemyShip',
    `locked=${player.locked}`,
  );
  check(
    'the lock control now offers to release the lock',
    locked.lockLabel === 'Unlock',
    `label=${locked.lockLabel}`,
  );

  // --- Arm. The colour must change before the tick that processes the order, so
  // the click is synchronised to just after a tick: that leaves a whole tick of
  // budget for the optimistic colour to appear, and the tick number at the flip
  // is the proof it beat the snapshot.
  const tickBeforeArming = tickOf((await state()).scenario);
  for (let i = 0; i < 40; i++) {
    if (tickOf((await state()).scenario) > tickBeforeArming) break;
    await sleep(50);
  }
  const beforeArming = await state();
  await evaluate(`document.querySelector('.fire-toggle').click()`);
  let optimistic = null;
  for (let i = 0; i < 40 && !optimistic; i++) {
    const probe = await state();
    if (/armed/.test(probe.toggleClass)) optimistic = probe;
    else await sleep(30);
  }
  await sleep(1600);
  const armed = await state();
  check(
    'the toggle shows armed before the tick that processes the order',
    optimistic !== null &&
      tickOf(optimistic.scenario) === tickOf(beforeArming.scenario) &&
      gunneryFor(optimistic.gunnery, 'Player').armed === false,
    `flip at ${tickOf(optimistic?.scenario)} vs click at ${tickOf(beforeArming.scenario)}, class=${optimistic?.toggleClass}`,
  );
  check(
    'the order reaches the snapshot and the guns are permitted to fire',
    gunneryFor(armed.gunnery, 'Player').armed === true,
    armed.gunnery,
  );

  // --- While the guns are loaded with the target still out of reach, the wedge
  // is the full envelope filled to the rim: the issue's "full and unhighlighted"
  // case, and the picture the look-check wants for a loaded envelope.
  if (armed.picture && gunneryFor(armed.gunnery, 'Player').reload === 0) {
    writeFileSync(LOADED_OUT, Buffer.from(armed.picture.split(',')[1], 'base64'));
    log(`picture: ${LOADED_OUT} (tick ${tickOf(armed.scenario)}, guns loaded)`);
  }

  // --- Wait for a volley: the player's shared reload starting is the proof one
  // left, and the enemy's hull dropping is the damage.
  let fired = null;
  let partway = null;
  for (let i = 0; i < 240; i++) {
    await sleep(500);
    const probe = await state();
    const player = gunneryFor(probe.gunnery, 'Player');
    const enemyHull = numberAfter(probe.enemy, 'Hull');
    if (!fired && player.reload !== null && player.reload > 0 && enemyHull !== null && enemyHull < 80) {
      fired = { tick: tickOf(probe.scenario), enemyHull, picture: probe.picture };
    }
    if (fired && player.reload !== null && player.reload > 0 && player.reload < player.reloadTotal) {
      partway = { ...probe, player };
      break;
    }
    if (fired && player.reload === 0) break;
  }
  check(
    'a volley leaves once the enemy comes into the envelope',
    fired !== null,
    fired ? `tick=${fired.tick} enemyHull=${fired.enemyHull}` : 'no volley within 120 s',
  );

  if (partway?.picture) {
    writeFileSync(OUT, Buffer.from(partway.picture.split(',')[1], 'base64'));
    log(`picture: ${OUT} (tick ${tickOf(partway.scenario)}, player reload ${partway.player.reload}/${partway.player.reloadTotal})`);
  } else if (fired?.picture) {
    writeFileSync(OUT, Buffer.from(fired.picture.split(',')[1], 'base64'));
    log(`picture: ${OUT} (tick ${fired.tick}, just fired)`);
  } else {
    check('a frame was captured while the envelope was on screen', false, 'no picture');
  }
  check(
    'a picture of the canvas was written',
    Boolean(partway?.picture || fired?.picture),
    OUT,
  );

  // --- Disengage mid-reload: the colour flips at once, the reload keeps running,
  // and no further volley lands.
  let disengaged = null;
  for (let i = 0; i < 8 && !disengaged; i++) {
    const probe = await state();
    const player = gunneryFor(probe.gunnery, 'Player');
    if (player.reload !== null && player.reload > 0) disengaged = probe;
    else await sleep(400);
  }
  if (disengaged) {
    const enemyHullBefore = numberAfter(disengaged.enemy, 'Hull');
    // Same tick-synchronised click as the arming check, for the same reason.
    const tickBeforeDisengaging = tickOf((await state()).scenario);
    for (let i = 0; i < 40; i++) {
      if (tickOf((await state()).scenario) > tickBeforeDisengaging) break;
      await sleep(50);
    }
    const beforeDisengaging = await state();
    await evaluate(`document.querySelector('.fire-toggle').click()`);
    let immediate = null;
    for (let i = 0; i < 40 && !immediate; i++) {
      const probe = await state();
      if (/disengaged/.test(probe.toggleClass)) immediate = probe;
      else await sleep(30);
    }
    check(
      'disengaging shows before the tick that processes the order, with arming still barred by the reload',
      immediate !== null &&
        tickOf(immediate.scenario) === tickOf(beforeDisengaging.scenario) &&
        immediate.toggleDisabled === true,
      `flip at ${tickOf(immediate?.scenario)} vs click at ${tickOf(beforeDisengaging.scenario)}, class=${immediate?.toggleClass} disabled=${immediate?.toggleDisabled}`,
    );
    let finished = null;
    for (let i = 0; i < 30; i++) {
      await sleep(500);
      const probe = await state();
      const player = gunneryFor(probe.gunnery, 'Player');
      if (player.reload === 0) {
        finished = probe;
        break;
      }
    }
    const enemyHullAfter = numberAfter((finished || await state()).enemy, 'Hull');
    check(
      'the reload still reaches zero while disengaged',
      finished !== null,
      `enemyHull ${enemyHullBefore} -> ${enemyHullAfter}`,
    );
    check(
      'no volley lands on the tick the reload completes once permission is withdrawn',
      enemyHullAfter === enemyHullBefore,
      `enemyHull ${enemyHullBefore} -> ${enemyHullAfter}`,
    );
    const rearmed = await state();
    check(
      'the control becomes clickable again once the sweep finishes',
      rearmed.toggleDisabled === false && /disengaged/.test(rearmed.toggleClass),
      `class=${rearmed.toggleClass} disabled=${rearmed.toggleDisabled}`,
    );
  } else {
    check('a reload was still running when the toggle was clicked', false, 'no reload to disengage during');
  }
}

// --- Final sanity: the simulation kept running through all of it.
const after = await state();
check(
  'the simulation keeps ticking through the loop',
  tickOf(after.scenario) !== null && tickOf(after.scenario) > 0,
  after.scenario,
);

const failures = results.filter((r) => !r.ok);
log(`${results.length - failures.length}/${results.length} checks passed`);
await S('Target.closeTarget', { targetId: created.result.targetId });
process.exit(failures.length === 0 ? 0 : 1);
