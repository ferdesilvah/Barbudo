// Barbudo multiplayer server: serves the web client and runs every table.
// The server is the only place that sees all hands; each browser gets its own redacted view.
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { WebSocketServer } from 'ws';
import { newGame, act, advance, view, botMove, ACTIVE, RuleError } from './shared/engine.js';

const ROOT = path.dirname(fileURLToPath(import.meta.url));
const env = (k, d) => (process.env[k] != null ? Number(process.env[k]) : d);
const CFG = {
  port: env('PORT', 8080),
  botDelay: env('BOT_DELAY_MS', 850),       // pause before a bot moves
  trickPause: env('TRICK_PAUSE_MS', 1500),  // finished trick stays on the table
  grace: env('GRACE_MS', 45_000),           // disconnected player's seat is held this long before a bot covers
  roundWait: env('ROUND_WAIT_MS', 30_000),  // results screen auto-continues after this
  idleRoomMs: env('IDLE_ROOM_MS', 6 * 3600_000),
  dataFile: process.env.DATA_FILE || path.join(ROOT, 'data', 'rooms.json'),
};
const PHRASES = ['¡Uy!', '¡Bien!', 'Jajaja', '¡Qué suerte!', 'Ya fue', '¡Vamos!'];
const BOT_NAMES = ['Pablo', 'Juan', 'María', 'Rosa', 'Lucho', 'Carmen'];
const CODE_CHARS = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // no 0/O, 1/I

/** @type {Map<string, any>} code → room */
const rooms = new Map();
/** token → {code, id} */
const tokens = new Map();
/** player id → socket */
const sockets = new Map();

// ─────────────────────────── Rooms ───────────────────────────
function newCode() {
  let code;
  do code = Array.from(crypto.randomBytes(5), b => CODE_CHARS[b % CODE_CHARS.length]).join('');
  while (rooms.has(code));
  return code;
}
const newId = () => crypto.randomBytes(6).toString('hex');
const cleanName = s => String(s || '').replace(/[<>]/g, '').trim().slice(0, 14) || 'Jugador';

function createRoom() {
  const room = { code: newCode(), hostId: null, seats: [], G: null, ready: [], touched: Date.now(), roundDeadline: null };
  rooms.set(room.code, room);
  return room;
}

function addHuman(room, name) {
  const seat = { id: newId(), name: cleanName(name), bot: false, token: crypto.randomBytes(16).toString('hex'),
                 color: nextColor(room), connected: true, left: false, offSince: null };
  room.seats.push(seat);
  tokens.set(seat.token, { code: room.code, id: seat.id });
  if (!room.hostId) room.hostId = seat.id;
  return seat;
}

function addBot(room) {
  const used = new Set(room.seats.map(s => s.name));
  const name = BOT_NAMES.find(n => !used.has(n)) || `Compu ${room.seats.length + 1}`;
  room.seats.push({ id: newId(), name, bot: true, color: nextColor(room), connected: true });
}

function nextColor(room) {
  const used = new Set(room.seats.map(s => s.color));
  for (let c = 0; c < 6; c++) if (!used.has(c)) return c;
  return room.seats.length % 6;
}

const seatIndex = (room, id) => (room.G ? room.G.players.findIndex(p => p.id === id) : -1);
const seatOf = (room, id) => room.seats.find(s => s.id === id);

/** A seat plays automatically if it's a bot, or its human left / has been gone past the grace period. */
function isCovered(seat, now = Date.now()) {
  if (seat.bot || seat.left) return true;
  return !seat.connected && seat.offSince != null && now - seat.offSince >= CFG.grace;
}

// ─────────────────────────── Broadcasting ───────────────────────────
function summary(room) {
  return {
    code: room.code, hostId: room.hostId,
    seats: room.seats.map(s => ({ id: s.id, name: s.name, bot: !!s.bot, color: s.color,
                                  connected: s.bot ? true : s.connected, covered: isCovered(s) })),
    started: !!room.G, ready: room.ready, roundDeadline: room.roundDeadline,
  };
}

function send(ws, msg) {
  if (ws && ws.readyState === 1) ws.send(JSON.stringify(msg));
}

function broadcast(room, ev = []) {
  const base = summary(room);
  for (const s of room.seats) {
    if (s.bot) continue;
    const ws = sockets.get(s.id);
    if (!ws) continue;
    send(ws, { t: 'room', ...base, you: s.id, view: room.G ? view(room.G, seatIndex(room, s.id)) : null, ev });
  }
  room.touched = Date.now();
  saveSoon();
}

// ─────────────────────────── Game flow ───────────────────────────
function startGame(room) {
  room.G = newGame(room.seats.map(s => ({ id: s.id, name: s.name, color: s.color })));
  room.ready = []; room.roundDeadline = null;
  broadcast(room, [{ e: 'start' }]);
  pump(room, 2500); // give everyone a moment to see the seat draw
}

function doAct(room, id, a) {
  const seat = seatIndex(room, id);
  const ev = act(room.G, seat, a);
  room.lastTrickAt = ev.some(e => e.e === 'trick') ? Date.now() : room.lastTrickAt;
  if (room.G.phase === 'roundScored') {
    room.ready = [];
    room.roundDeadline = Date.now() + CFG.roundWait + CFG.trickPause;
  }
  broadcast(room, ev);
  pump(room);
}

function doAdvance(room) {
  advance(room.G);
  room.ready = []; room.roundDeadline = null;
  broadcast(room, [{ e: 'next' }]);
  pump(room);
}

/** Schedules whatever happens next without a human: bot moves, covered seats, round auto-continue. */
function pump(room, extraDelay = 0) {
  clearTimeout(room.timer);
  const G = room.G;
  if (!G) return;
  const now = Date.now();

  if (G.phase === 'roundScored') {
    const humans = room.seats.filter(s => !isCovered(s, now) && s.connected);
    if (humans.every(s => room.ready.includes(s.id))) {
      room.timer = setTimeout(() => doAdvance(room), CFG.trickPause);
    } else {
      room.timer = setTimeout(() => { if (room.G?.phase === 'roundScored') doAdvance(room); }, Math.max(0, room.roundDeadline - now));
    }
    return;
  }
  if (!ACTIVE.includes(G.phase)) return;

  const actor = G.players[G.toAct], seat = seatOf(room, actor.id);
  const pauseLeft = room.lastTrickAt ? Math.max(0, room.lastTrickAt + CFG.trickPause - now) : 0;
  let wait;
  if (isCovered(seat, now)) wait = CFG.botDelay + pauseLeft + extraDelay;
  else if (!seat.connected && seat.offSince != null) wait = seat.offSince + CFG.grace - now + 50; // re-check when grace ends
  else return; // a connected human's turn: wait for them

  room.timer = setTimeout(() => {
    if (!room.G || !ACTIVE.includes(room.G.phase)) return;
    const cur = room.G.players[room.G.toAct];
    if (cur.id !== actor.id) return pump(room);
    if (isCovered(seatOf(room, cur.id))) {
      try { doAct(room, cur.id, botMove(room.G, room.G.toAct)); }
      catch (err) { console.error('bot move failed', err); }
    } else {
      broadcast(room); // grace ended mid-wait: refresh "covered" badges, then decide again
      pump(room);
    }
  }, Math.max(0, wait));
}

// ─────────────────────────── Messages ───────────────────────────
function handle(ws, msg) {
  const me = ws.player && tokens.has(ws.player.token) ? ws.player : null;
  const room = me ? rooms.get(me.code) : null;
  const fail = (text, code = 'error') => send(ws, { t: 'error', code, text });

  switch (msg.t) {
    case 'hello': { // reconnect with a saved token
      const ref = tokens.get(String(msg.token || ''));
      const r = ref && rooms.get(ref.code), s = r && seatOf(r, ref.id);
      if (!s || s.left) return send(ws, { t: 'welcome', token: null });
      bind(ws, s, r);
      send(ws, { t: 'welcome', token: s.token, code: r.code });
      broadcast(r); pump(r);
      return;
    }
    case 'create': {
      leaveCurrent(ws);
      const r = createRoom(), s = addHuman(r, msg.name);
      bind(ws, s, r);
      send(ws, { t: 'welcome', token: s.token, code: r.code });
      if (msg.solo) { addBot(r); addBot(r); addBot(r); startGame(r); } else broadcast(r);
      return;
    }
    case 'join': {
      const r = rooms.get(String(msg.code || '').toUpperCase().trim());
      if (!r) return fail('No encontramos esa mesa. Revisa el código.', 'noRoom');
      if (r.G) return fail('Esa mesa ya empezó a jugar.', 'started');
      if (r.seats.length >= 6) return fail('La mesa está llena (6 jugadores).', 'full');
      leaveCurrent(ws);
      const s = addHuman(r, msg.name);
      bind(ws, s, r);
      send(ws, { t: 'welcome', token: s.token, code: r.code });
      broadcast(r);
      return;
    }
  }

  if (!me || !room) return fail('Primero entra a una mesa.', 'noSeat');
  const isHost = room.hostId === me.id;

  try {
    switch (msg.t) {
      case 'addBot':
        if (!isHost || room.G) return;
        if (room.seats.length >= 6) return fail('La mesa está llena.');
        addBot(room); broadcast(room); return;
      case 'kick': {
        if (!isHost || room.G) return;
        const s = seatOf(room, msg.id);
        if (!s || s.id === me.id) return;
        room.seats = room.seats.filter(x => x !== s);
        if (s.token) { tokens.delete(s.token); send(sockets.get(s.id), { t: 'kicked' }); sockets.delete(s.id); }
        broadcast(room); return;
      }
      case 'start':
        if (!isHost || room.G) return;
        if (room.seats.length < 3) return fail('Se necesitan al menos 3 jugadores. Agrega a la compu.');
        startGame(room); return;
      case 'cut': case 'bid': case 'play':
        if (!room.G) return;
        if (room.lastTrickAt && Date.now() - room.lastTrickAt < CFG.trickPause - 200) return fail('Un momento…', 'pause');
        doAct(room, me.id, msg.t === 'cut' ? { t: 'cut', at: msg.at } : msg.t === 'bid' ? { t: 'bid', n: msg.n } : { t: 'play', card: msg.card });
        return;
      case 'ready':
        if (room.G?.phase !== 'roundScored') return;
        if (!room.ready.includes(me.id)) room.ready.push(me.id);
        broadcast(room); pump(room); return;
      case 'rematch':
        if (!isHost || room.G?.phase !== 'gameOver') return;
        room.G = null; room.ready = []; room.lastTrickAt = null;
        room.seats = room.seats.filter(s => s.bot || !s.left);
        broadcast(room); return;
      case 'react':
        if (!PHRASES.includes(msg.text)) return;
        for (const s of room.seats) if (!s.bot) send(sockets.get(s.id), { t: 'react', id: me.id, text: msg.text });
        return;
      case 'leave':
        leaveCurrent(ws);
        send(ws, { t: 'left' });
        return;
    }
  } catch (err) {
    if (err instanceof RuleError) return fail(err.message, err.code);
    console.error(err);
    fail('Algo salió mal en el servidor.');
  }
}

function bind(ws, seat, room) {
  const old = sockets.get(seat.id);
  if (old && old !== ws) { send(old, { t: 'replaced' }); old.player = null; old.close(); }
  sockets.set(seat.id, ws);
  ws.player = { id: seat.id, code: room.code, token: seat.token };
  seat.connected = true; seat.offSince = null;
}

function leaveCurrent(ws) {
  const p = ws.player;
  if (!p) return;
  const room = rooms.get(p.code), seat = room && seatOf(room, p.id);
  ws.player = null;
  sockets.delete(p.id);
  if (!seat) return;
  tokens.delete(seat.token);
  if (!room.G) {
    room.seats = room.seats.filter(s => s !== seat);
  } else {
    seat.left = true; seat.connected = false; seat.offSince = Date.now();
  }
  const humans = room.seats.filter(s => !s.bot && !s.left);
  if (!humans.length) { clearTimeout(room.timer); rooms.delete(room.code); saveSoon(); return; }
  if (room.hostId === seat.id) room.hostId = humans[0].id;
  broadcast(room); pump(room);
}

function onClose(ws) {
  const p = ws.player;
  if (!p || sockets.get(p.id) !== ws) return;
  sockets.delete(p.id);
  const room = rooms.get(p.code), seat = room && seatOf(room, p.id);
  if (!seat) return;
  seat.connected = false; seat.offSince = Date.now();
  broadcast(room); pump(room);
}

// ─────────────────────────── Persistence ───────────────────────────
let saveTimer = null;
function saveSoon() {
  clearTimeout(saveTimer);
  saveTimer = setTimeout(() => {
    const data = [...rooms.values()].map(({ timer, ...r }) => r);
    fs.mkdirSync(path.dirname(CFG.dataFile), { recursive: true });
    fs.writeFile(CFG.dataFile + '.tmp', JSON.stringify(data), err => {
      if (!err) fs.rename(CFG.dataFile + '.tmp', CFG.dataFile, () => {});
    });
  }, 1000);
}
function load() {
  try {
    const data = JSON.parse(fs.readFileSync(CFG.dataFile, 'utf8'));
    for (const r of data) {
      r.seats.forEach(s => {
        if (s.token) tokens.set(s.token, { code: r.code, id: s.id });
        if (!s.bot) { s.connected = false; s.offSince = Date.now(); }
      });
      rooms.set(r.code, r);
      pump(r);
    }
    console.log(`Restored ${rooms.size} table(s)`);
  } catch { /* first run */ }
}
setInterval(() => {
  const cutoff = Date.now() - CFG.idleRoomMs;
  for (const [code, r] of rooms) if (r.touched < cutoff) { clearTimeout(r.timer); rooms.delete(code); r.seats.forEach(s => s.token && tokens.delete(s.token)); }
}, 10 * 60_000).unref();

// ─────────────────────────── HTTP + WebSocket ───────────────────────────
const TYPES = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.css': 'text/css; charset=utf-8',
                '.svg': 'image/svg+xml', '.png': 'image/png', '.json': 'application/json', '.webmanifest': 'application/manifest+json' };

const server = http.createServer((req, res) => {
  const url = new URL(req.url, 'http://x');
  // Open to any origin: the pages may be served from a static host while the game lives here, and
  // this is how a browser checks whether we're awake. It says nothing but "ok". (WebSockets don't
  // go through CORS at all, so /ws needs nothing.)
  if (url.pathname === '/healthz') {
    res.writeHead(200, { 'content-type': 'text/plain', 'access-control-allow-origin': '*' });
    return res.end('ok');
  }
  let rel = url.pathname === '/' || /^\/m\/[A-Z0-9]{5}$/i.test(url.pathname) ? '/index.html' : url.pathname;
  const base = rel.startsWith('/shared/') ? ROOT : path.join(ROOT, 'public');
  const file = path.normalize(path.join(base, rel));
  if (!file.startsWith(base)) { res.writeHead(403); return res.end(); }
  fs.readFile(file, (err, body) => {
    if (err) { res.writeHead(404, { 'content-type': 'text/plain' }); return res.end('No existe'); }
    res.writeHead(200, { 'content-type': TYPES[path.extname(file)] || 'application/octet-stream', 'cache-control': 'no-cache' });
    res.end(body);
  });
});

const wss = new WebSocketServer({ server, path: '/ws', maxPayload: 4096 });
wss.on('connection', ws => {
  ws.isAlive = true;
  ws.on('pong', () => { ws.isAlive = true; });
  ws.on('message', raw => {
    let msg;
    try { msg = JSON.parse(raw); } catch { return; }
    if (msg && typeof msg.t === 'string') handle(ws, msg);
  });
  ws.on('close', () => onClose(ws));
});
// Drop dead connections (phone locked, Wi-Fi gone) so seats show as disconnected.
setInterval(() => {
  for (const ws of wss.clients) {
    if (!ws.isAlive) { ws.terminate(); continue; }
    ws.isAlive = false; ws.ping();
  }
}, 20_000).unref();

export function start(port = CFG.port) {
  load();
  return new Promise(resolve => server.listen(port, () => resolve(server)));
}
export function stop() {
  for (const r of rooms.values()) clearTimeout(r.timer);
  wss.clients.forEach(ws => ws.terminate());
  return new Promise(resolve => server.close(resolve));
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  start().then(s => console.log(`Barbudo en http://localhost:${s.address().port}`));
}
