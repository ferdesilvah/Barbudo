import { test } from 'node:test';
import assert from 'node:assert/strict';
import { newGame, act, advance, view, botMove, score, scheduleFor, legalBids, handSize, cid } from '../shared/engine.js';

const players = n => ['Pedro', 'Pablo', 'Juan', 'María', 'Rosa', 'Lucho'].slice(0, n).map((name, i) => ({ id: 'p' + i, name, color: i }));

test('round schedule matches the rulebook', () => {
  assert.deepEqual([3, 4, 5, 6].map(n => scheduleFor(n).length), [19, 16, 14, 13]);
  assert.equal(Math.max(...scheduleFor(4)), 13);
});

test('scoring, including the rulebook example', () => {
  assert.equal(score(3, 3), 3); assert.equal(score(0, 0), 1);
  assert.equal(score(3, 1), -3); assert.equal(score(1, 4), -4);
  const rounds = [[[1, 0], [1, 1], [0, 0], [0, 0]], [[0, 0], [1, 1], [1, 0], [1, 1]], [[2, 2], [1, 0], [0, 1], [0, 0]]];
  const tot = [0, 0, 0, 0], table = [];
  for (const r of rounds) { r.forEach(([b, t], i) => { tot[i] += score(b, t); }); table.push([...tot]); }
  assert.deepEqual(table, [[-1, 1, 1, 1], [0, 2, 0, 2], [2, 1, -1, 3]]);
});

test('bots finish full games with every invariant holding', () => {
  for (let n = 3; n <= 6; n++) {
    for (let seed = 1; seed <= 150; seed++) {
      const G = newGame(players(n), seed);
      let steps = 0;
      while (G.phase !== 'gameOver') {
        assert.ok(++steps < 5000, 'game terminates');
        if (G.phase === 'roundScored') {
          assert.equal(G.tricks.reduce((a, b) => a + b, 0), handSize(G));
          advance(G); continue;
        }
        const before = G.phase, s = G.toAct;
        act(G, s, botMove(G, s));
        if (before === 'cutting') {
          assert.ok(G.hands.every(h => h.length === handSize(G)));
          assert.equal(G.hands.flat().length + G.stock.length, 52);
          if (!G.stock.length) {
            assert.equal(G.trumpHolder, G.dealer, 'cut card lands with the dealer');
            assert.ok(G.hands[G.dealer].some(c => cid(c) === cid(G.trump)));
          }
        }
        if (before === 'bidding' && G.phase === 'playing') assert.notEqual(G.bids.reduce((a, b) => a + b, 0), handSize(G));
      }
      assert.equal(G.scores.length, scheduleFor(n).length);
      JSON.parse(JSON.stringify(G)); // stays serializable
    }
  }
});

test('illegal moves throw and change nothing', () => {
  const G = newGame(players(4), 7);
  const snap = JSON.stringify(G);
  assert.throws(() => act(G, (G.toAct + 1) % 4, { t: 'cut', at: 10 }), /turno/);
  assert.throws(() => act(G, G.toAct, { t: 'bid', n: 0 }));
  assert.equal(JSON.stringify(G), snap);
  act(G, G.toAct, { t: 'cut', at: 20 });
  // round 1: after three passes the dealer may not bid 1 (total would equal the hand size)
  for (let i = 0; i < 3; i++) act(G, G.toAct, { t: 'bid', n: 0 });
  assert.deepEqual(legalBids(G, G.toAct), [0], 'total 0 of 1 is fine; 1 would make it equal');
});

test('a view never contains another player\'s cards', () => {
  const G = newGame(players(4), 11);
  act(G, G.toAct, { t: 'cut', at: 30 });
  for (let s = 0; s < 4; s++) {
    const v = view(G, s), json = JSON.stringify(v);
    assert.equal(v.myHand.length, 1);
    for (let o = 0; o < 4; o++) if (o !== s) {
      const other = cid(G.hands[o][0]);
      if (!(G.trump && other === cid(G.trump))) assert.ok(!json.includes(`"${other}"`) && !json.includes(JSON.stringify(G.hands[o][0])), 'no leak');
    }
    assert.equal(v.deck, undefined); assert.equal(v.stock, undefined); assert.equal(v.rs, undefined);
  }
});
