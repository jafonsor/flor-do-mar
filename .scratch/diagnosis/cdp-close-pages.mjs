// Helper: close every open page on the client's URL, so an experiment starts from
// a known number of live widget sessions.
const version = await (await fetch('http://127.0.0.1:9224/json/version')).json();
const ws = new WebSocket(version.webSocketDebuggerUrl);
await new Promise((res, rej) => {
  ws.onopen = res;
  ws.onerror = () => rej(new Error('ws fail'));
});
let id = 1;
const pending = new Map();
ws.onmessage = (ev) => {
  const m = JSON.parse(typeof ev.data === 'string' ? ev.data : '');
  if (m.id && pending.has(m.id)) {
    pending.get(m.id)(m);
    pending.delete(m.id);
  }
};
const send = (method, params = {}) =>
  new Promise((resolve) => {
    const myId = id++;
    pending.set(myId, resolve);
    ws.send(JSON.stringify({ id: myId, method, params }));
  });

const targets = (await send('Target.getTargets')).result.targetInfos.filter(
  (t) => t.type === 'page' && t.url.includes('3911'),
);
for (const t of targets) {
  await send('Target.closeTarget', { targetId: t.targetId });
  console.log(`closed ${t.targetId.slice(0, 8)}`);
}
console.log(`closed ${targets.length} page(s)`);
process.exit(0);
