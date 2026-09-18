// Full games over real WebSockets: several "family members" in separate connections,
// a bot filling a seat, a player dropping and reconnecting mid-game.
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import os from 'node:os';
import path from 'node:path';
import WebSocket from 'ws';

process.env.BOT_DELAY_MS = '5';
process.env.TRICK_PAUSE_MS = '0';
process.env.ROUND_WAIT_MS = '50';
process.env.GRACE_MS = '300';
process.env.DATA_FILE = path.join(os.tmpdir(), `barbudo-test-${process.pid}.json`);
const { start, stop } = await import('../server.js');

let port;
before(async () => { port = (await start(0)).address().port; });
after(() => stop());

/** A scripted family member: plays legal moves whenever it's their turn. */
class Player {
  constructor(name) { this.name = name; this.msgs = []; this.last = null; this.waiters = []; this.autoplay = true; this.cheats = []; }
  connect() {
    this.ws = new WebSocket(`ws://localhost:${port}/ws`);
    this.ws.on('message', raw => {
      const m = JSON.parse(raw);
      this.msgs.push(m);
      if (m.t === 'welcome') { this.token = m.token; this.code = m.code; }
      if (m.t === 'room') { this.last = m; this.onRoom(m); }
      this.waiters = this.waiters.filter(w => !w(m));
    });
    return new Promise(r => this.ws.on('open', r));
  }
  send(m) { this.ws.send(JSON.stringify(m)); }
  wait(pred, ms = 20000) {
    return new Promise((resolve, reject) => {
      const t = setTimeout(() => reject(new Error(`${this.name}: timed out`)), ms);
      if (this.last && pred(this.last)) { clearTimeout(t); return resolve(this.last); }
      this.waiters.push(m => (m.t === 'room' && pred(m) ? (clearTimeout(t), resolve(m), true) : false));
    });
  }
  onRoom(m) {
    const v = m.view;
    if (!v || !this.autoplay) return;
    // Hidden information check: only our own hand is ever sent.
    if (v.myHand.length !== v.handCounts[v.mySeat]) this.cheats.push('hand mismatch');
    if (v.phase === 'roundScored' && !m.ready.includes(m.you)) return this.send({ t: 'ready' });
    if (v.toAct !== v.mySeat) return;
    if (v.phase === 'cutting') this.send({ t: 'cut', at: 17 });
    else if (v.phase === 'bidding' && v.legalBids.length) this.send({ t: 'bid', n: v.legalBids[0] });
    else if (v.phase === 'playing' && v.legalCards.length) this.send({ t: 'play', card: v.legalCards[v.legalCards.length - 1] });
  }
  close() { this.ws.close(); }
}

test('three relatives + one bot play a whole game; everyone sees the same result', async () => {
  const [ana, beto, caro] = ['Ana', 'Beto', 'Caro'].map(n => new Player(n));
  await Promise.all([ana, beto, caro].map(p => p.connect()));

  ana.send({ t: 'create', name: 'Ana' });
  await ana.wait(m => m.seats.length === 1);
  assert.match(ana.code, /^[A-Z2-9]{5}$/);

  beto.send({ t: 'join', code: ana.code.toLowerCase(), name: 'Beto' });
  caro.send({ t: 'join', code: ana.code, name: 'Caro' });
  await ana.wait(m => m.seats.length === 3);

  caro.send({ t: 'start' }); // not the host: ignored
  ana.send({ t: 'addBot' });
  await ana.wait(m => m.seats.length === 4 && m.seats.some(s => s.bot));
  ana.send({ t: 'start' });

  const results = await Promise.all([ana, beto, caro].map(p => p.wait(m => m.view?.phase === 'gameOver', 60000)));
  const totals = results.map(m => JSON.stringify(m.view.totals));
  assert.equal(new Set(totals).size, 1, 'all clients agree on the final score');
  assert.equal(results[0].view.scores.length, 16, '4 players → 16 rounds');
  for (const p of [ana, beto, caro]) assert.deepEqual(p.cheats, []);

  // Host can set up a rematch with the same people.
  ana.send({ t: 'rematch' });
  await ana.wait(m => m.started === false);
  [ana, beto, caro].forEach(p => p.close());
});

test('a player who drops out is covered by a bot, then reclaims the seat with their token', async () => {
  const host = new Player('Host'), flaky = new Player('Flaky');
  await host.connect(); await flaky.connect();
  host.send({ t: 'create', name: 'Host' });
  await host.wait(m => m.seats.length === 1);
  flaky.send({ t: 'join', code: host.code, name: 'Flaky' });
  await host.wait(m => m.seats.length === 2);
  host.send({ t: 'addBot' });
  await host.wait(m => m.seats.length === 3);
  host.send({ t: 'start' });
  await flaky.wait(m => m.view?.round >= 1, 30000);

  // Flaky's phone locks.
  flaky.autoplay = false;
  flaky.close();
  await host.wait(m => m.seats.find(s => s.name === 'Flaky' && !s.connected));
  const covered = await host.wait(m => m.seats.find(s => s.name === 'Flaky' && s.covered));
  assert.ok(covered, 'bot covers after the grace period');
  const roundBefore = covered.view.round;
  await host.wait(m => m.view.round >= roundBefore + 1, 30000); // game keeps moving without them

  // Flaky comes back.
  const back = new Player('Flaky');
  await back.connect();
  back.send({ t: 'hello', token: flaky.token });
  const m = await back.wait(x => x.view != null);
  assert.equal(m.seats.find(s => s.id === m.you).name, 'Flaky');
  assert.equal(m.view.myHand.length, m.view.handCounts[m.view.mySeat]);
  await host.wait(x => x.seats.find(s => s.name === 'Flaky' && s.connected && !s.covered));
  await Promise.all([host, back].map(p => p.wait(x => x.view?.phase === 'gameOver', 60000)));
  host.close(); back.close();
});

test('bad input gets friendly errors', async () => {
  const p = new Player('Solo');
  await p.connect();
  p.send({ t: 'join', code: 'ZZZZZ', name: 'x' });
  const err = await new Promise(r => { const i = setInterval(() => { const e = p.msgs.find(m => m.t === 'error'); if (e) { clearInterval(i); r(e); } }, 10); });
  assert.equal(err.code, 'noRoom');
  p.send({ t: 'create', name: 'Solo', solo: true }); // quick game vs 3 bots
  const m = await p.wait(x => x.view?.phase === 'gameOver', 60000);
  assert.equal(m.seats.filter(s => s.bot).length, 3);
  p.close();
});
