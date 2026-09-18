// Barbudo rules engine — JavaScript twin of Sources/BarbudoCore.
// Pure and deterministic: the whole game is one plain JSON object `G`, including the RNG
// state, so the server can save it to disk and restore it after a restart.

export const SUITS = ['S', 'D', 'C', 'H'];
export const rsym = r => ({ 11: 'J', 12: 'Q', 13: 'K', 14: 'A' })[r] || String(r);
export const cid = c => rsym(c.r) + c.s;
export const fullDeck = () => SUITS.flatMap(s => Array.from({ length: 13 }, (_, i) => ({ r: i + 2, s })));
export const scheduleFor = n => {
  const m = Math.floor(52 / n);
  return [...Array.from({ length: m }, (_, i) => i + 1), ...Array(n - 1).fill(m)];
};
export const ACTIVE = ['cutting', 'bidding', 'playing'];

export class RuleError extends Error {
  constructor(code, msg) { super(msg || code); this.code = code; }
}

// mulberry32; state lives in G.rs so G stays serializable
function rand(G) {
  let t = G.rs = (G.rs + 0x6D2B79F5) | 0;
  t = Math.imul(t ^ t >>> 15, 1 | t);
  t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t;
  return ((t ^ t >>> 14) >>> 0) / 4294967296;
}
function shuffle(a, G) {
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(rand(G) * (i + 1));
    [a[i], a[j]] = [a[j], a[i]];
  }
  return a;
}

const count = G => G.players.length;
export const handSize = G => G.schedule[G.round];
export const trumpSuit = G => (G.trump ? G.trump.s : null);
export const totals = G => G.players.map((_, s) => G.scores.reduce((a, r) => a + r[s], 0));
export const score = (bid, took) => (took === bid ? (bid === 0 ? 1 : bid) : took < bid ? -bid : -took);
export const beats = (a, b, ts) => (a.s === b.s ? a.r > b.r : a.s === ts);
export function winIdx(trick, ts) {
  let w = 0;
  for (let i = 1; i < trick.length; i++) if (beats(trick[i].card, trick[w].card, ts)) w = i;
  return w;
}

/**
 * New game. `players` = [{id, name, color}] in join order. Everyone draws a card; tied
 * ranks redraw; the highest card sits first and deals round 1; seats follow by card value.
 */
export function newGame(players, seed = (Math.random() * 2 ** 32) | 0) {
  if (players.length < 3 || players.length > 6) throw new RuleError('playerCount', 'Barbudo es para 3 a 6 jugadores');
  const G = {
    v: 1, seq: 0, rs: seed | 0,
    players: players.map(p => ({ id: p.id, name: p.name, color: p.color })),
    phase: 'cutting', schedule: scheduleFor(players.length), round: 0, dealer: 0, toAct: 0,
    hands: [], stock: [], deck: [], trump: null, trumpHolder: null,
    bids: [], tricks: [], trick: [], lastTrick: null, scores: [], draws: [],
  };
  const pool = shuffle(fullDeck(), G), draws = {};
  let need = G.players.map(p => p.id);
  while (need.length) {
    need.forEach(id => { draws[id] = pool.pop(); });
    const byRank = {};
    Object.entries(draws).forEach(([id, c]) => (byRank[c.r] = byRank[c.r] || []).push(id));
    need = Object.values(byRank).filter(ids => ids.length > 1).flat();
  }
  G.players.sort((a, b) => draws[b.id].r - draws[a.id].r);
  G.draws = G.players.map(p => ({ id: p.id, card: draws[p.id] }));
  startRound(G);
  return G;
}

function startRound(G) {
  const n = count(G);
  G.deck = shuffle(fullDeck(), G);
  G.hands = G.players.map(() => []);
  G.stock = []; G.trump = null; G.trumpHolder = null;
  G.bids = G.players.map(() => null);
  G.tricks = G.players.map(() => 0);
  G.trick = []; G.lastTrick = null;
  G.phase = 'cutting';
  G.toAct = (G.dealer + n - 1) % n; // the player on the dealer's right cuts
}

export function legalBids(G, seat) {
  if (G.phase !== 'bidding' || seat !== G.toAct) return [];
  const h = handSize(G), placed = G.bids.filter(b => b != null);
  let bids = Array.from({ length: h + 1 }, (_, i) => i);
  if (placed.length === count(G) - 1) {
    const forbidden = h - placed.reduce((a, b) => a + b, 0); // hook rule: last bidder
    bids = bids.filter(b => b !== forbidden);
  }
  return bids;
}

export function legalCards(G, seat) {
  if (G.phase !== 'playing' || seat !== G.toAct) return [];
  const hand = G.hands[seat];
  if (!G.trick.length) return hand;
  const led = G.trick[0].card.s, follow = hand.filter(c => c.s === led);
  return follow.length ? follow : hand;
}

/**
 * Apply one player's move. `a` is {t:'cut', at} | {t:'bid', n} | {t:'play', card:'AS'}.
 * Throws RuleError (state untouched) if illegal. Returns events for the UI to animate.
 */
export function act(G, seat, a) {
  if (!ACTIVE.includes(G.phase)) throw new RuleError('wrongPhase');
  if (seat !== G.toAct) throw new RuleError('notYourTurn', 'No es tu turno');
  const n = count(G), ev = [];

  if (a.t === 'cut') {
    if (G.phase !== 'cutting') throw new RuleError('wrongPhase');
    const at = Number(a.at);
    if (!Number.isInteger(at) || at < 1 || at > 51) throw new RuleError('invalidCut');
    const deck = G.deck.slice(at).concat(G.deck.slice(0, at));
    const h = handSize(G), start = (G.dealer + 1) % n, dealt = h * n;
    for (let i = 0; i < dealt; i++) G.hands[(start + i) % n].push(deck[i]);
    G.stock = deck.slice(dealt);
    if (G.stock.length) G.trump = G.stock[0];
    else { G.trump = deck[deck.length - 1]; G.trumpHolder = (start + dealt - 1) % n; } // cut card → dealer's last card
    G.deck = []; G.phase = 'bidding'; G.toAct = start;
    ev.push({ e: 'dealt', seat });
  } else if (a.t === 'bid') {
    if (G.phase !== 'bidding') throw new RuleError('wrongPhase');
    const b = Number(a.n);
    if (!legalBids(G, seat).includes(b)) throw new RuleError('illegalBid', 'Ese pedido no está permitido');
    G.bids[seat] = b;
    if (G.bids.every(x => x != null)) { G.phase = 'playing'; G.toAct = (G.dealer + 1) % n; }
    else G.toAct = (seat + 1) % n;
    ev.push({ e: 'bid', seat, n: b });
  } else if (a.t === 'play') {
    if (G.phase !== 'playing') throw new RuleError('wrongPhase');
    const hand = G.hands[seat], i = hand.findIndex(c => cid(c) === a.card);
    if (i < 0 || !legalCards(G, seat).some(c => cid(c) === a.card)) throw new RuleError('illegalCard', 'Tienes que seguir el palo');
    const ts = trumpSuit(G), led = G.trick.length ? G.trick[0].card.s : null;
    const [card] = hand.splice(i, 1);
    G.trick.push({ seat, card });
    if (G.trumpHolder === seat && G.trump && cid(card) === cid(G.trump)) G.trumpHolder = null;
    const callout = card.s === ts ? (led == null ? '¡Arrastró!' : led !== ts ? '¡Chancó!' : null) : null;
    ev.push({ e: 'card', seat, card, callout });
    if (G.trick.length < n) G.toAct = (seat + 1) % n;
    else {
      const trick = G.trick, w = trick[winIdx(trick, ts)].seat;
      G.tricks[w]++; G.lastTrick = trick; G.trick = [];
      ev.push({ e: 'trick', seat: w, trick });
      if (!G.hands[w].length) {
        G.scores.push(G.players.map((_, s) => score(G.bids[s], G.tricks[s])));
        G.phase = 'roundScored';
        ev.push({ e: 'round' });
      } else G.toAct = w;
    }
  } else throw new RuleError('badAction');

  G.seq++;
  return ev;
}

/** Leave the results screen: next round, or game over after the last one. */
export function advance(G) {
  if (G.phase !== 'roundScored') throw new RuleError('wrongPhase');
  if (G.round === G.schedule.length - 1) G.phase = 'gameOver';
  else { G.round++; G.dealer = (G.dealer + 1) % count(G); startRound(G); }
  G.seq++;
}

/** What one seat may see. Never includes other hands, the deck, the stock, or the RNG. */
export function view(G, seat) {
  const mine = seat != null && seat >= 0;
  return {
    seq: G.seq, phase: G.phase, schedule: G.schedule, round: G.round, dealer: G.dealer, toAct: G.toAct,
    mySeat: mine ? seat : null,
    players: G.players.map(p => ({ id: p.id, name: p.name, color: p.color })),
    myHand: mine ? G.hands[seat].slice() : [],
    handCounts: G.hands.map(h => h.length),
    trump: G.trump, trumpHolder: G.trumpHolder,
    bids: G.bids, tricks: G.tricks, trick: G.trick, lastTrick: G.lastTrick,
    scores: G.scores, totals: totals(G), draws: G.draws,
    legalBids: mine ? legalBids(G, seat) : [],
    legalCards: mine ? legalCards(G, seat).map(cid) : [],
  };
}

// ── Bot (same heuristic as HeuristicBot in Swift). Reads only its own hand + public info.
export function botMove(G, seat) {
  if (G.phase === 'cutting') return { t: 'cut', at: 8 + Math.floor(Math.random() * 37) };
  const ts = trumpSuit(G), hand = G.hands[seat];
  if (G.phase === 'bidding') {
    let e = 0;
    hand.forEach(c => {
      const len = hand.filter(d => d.s === c.s).length;
      if (c.s === ts) e += c.r >= 11 ? 0.9 : 0.4;
      else if (c.r === 14) e += len <= 4 ? 0.85 : 0.6;
      else if (c.r === 13) e += len <= 3 ? 0.4 : 0.2;
    });
    e *= Math.sqrt(4 / Math.max(count(G), 4));
    const n = legalBids(G, seat).reduce((best, b) => (Math.abs(b - e) < Math.abs(best - e) ? b : best));
    return { t: 'bid', n };
  }
  const strength = c => (c.s === ts ? 100 : 0) + c.r;
  const bs = [...legalCards(G, seat)].sort((a, b) => strength(a) - strength(b));
  const need = G.bids[seat] - G.tricks[seat];
  let pick;
  if (!G.trick.length) pick = need > 0 ? bs[bs.length - 1] : bs[0];
  else {
    const best = G.trick[winIdx(G.trick, ts)].card;
    const win = bs.filter(c => beats(c, best, ts)), lose = bs.filter(c => !beats(c, best, ts));
    pick = need > 0 ? (win[0] || bs[0]) : (lose[lose.length - 1] || win[0]);
  }
  return { t: 'play', card: cid(pick) };
}
