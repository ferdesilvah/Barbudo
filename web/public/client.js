// Barbudo web client. Renders whatever the server says this seat may see (`view`)
// and sends intents back. It never decides game outcomes itself.

const GLYPH = { S: '♠︎', H: '♥︎', D: '♦︎', C: '♣︎' };
const SUIT_NAME = { S: 'espadas', H: 'corazones', D: 'diamantes', C: 'tréboles' };
const rsym = r => ({ 11: 'J', 12: 'Q', 13: 'K', 14: 'A' })[r] || String(r);
const isRed = s => s === 'H' || s === 'D';
const cid = c => rsym(c.r) + c.s;
const COLORS = [['var(--teal)', 'var(--cream)'], ['var(--sage)', 'var(--ink)'], ['var(--gold)', 'var(--ink)'], ['var(--plum)', 'var(--cream)'], ['var(--terra)', 'var(--cream)'], ['var(--dusk)', 'var(--cream)']];
const PHRASES = ['¡Uy!', '¡Bien!', 'Jajaja', '¡Qué suerte!', 'Ya fue', '¡Vamos!'];
const ACTIVE = ['cutting', 'bidding', 'playing'];
const TRICK_SHOW = 1100, SWEEP = 400;

const app = document.getElementById('app');
const connEl = document.getElementById('conn');
const toastEl = document.getElementById('toast');

// ─────────────────────────── State ───────────────────────────
const store = {
  get() { try { return JSON.parse(localStorage.getItem('barbudo') || '{}'); } catch { return {}; } },
  set(patch) { try { localStorage.setItem('barbudo', JSON.stringify({ ...store.get(), ...patch })); } catch { /* private mode */ } },
};
const saved = store.get();
const invitedCode = (location.pathname.match(/^\/m\/([A-Za-z0-9]{5})$/) || [])[1]?.toUpperCase() || null;

const S = { ws: null, online: false, retry: 0, token: saved.token || null, name: saved.name || '', room: null, V: null, screen: 'home' };
const UI = { sel: null, bid: null, pausing: false, sweeping: false, shown: [], winner: null, callout: null,
             overlay: null, tray: false, reacts: {}, lastSeq: -1, drawTimer: null, pauseTimer: null };

// ─────────────────────────── Connection ───────────────────────────
function connect() {
  const ws = new WebSocket(`${location.protocol === 'https:' ? 'wss' : 'ws'}://${location.host}/ws`);
  S.ws = ws;
  ws.onopen = () => {
    S.online = true; S.retry = 0; connEl.hidden = true;
    if (S.token) send({ t: 'hello', token: S.token });
    else render();
  };
  ws.onmessage = e => { try { onMessage(JSON.parse(e.data)); } catch (err) { console.error(err); } };
  ws.onclose = () => {
    S.online = false;
    if (S.screen !== 'home') connEl.hidden = false;
    const wait = Math.min(1000 * 2 ** S.retry++, 8000);
    setTimeout(connect, wait);
  };
}
const send = m => { if (S.ws && S.ws.readyState === 1) S.ws.send(JSON.stringify(m)); };
document.addEventListener('visibilitychange', () => {
  if (document.visibilityState === 'visible' && S.ws && S.ws.readyState > 1) connect();
});

function onMessage(m) {
  switch (m.t) {
    case 'welcome':
      S.token = m.token; store.set({ token: m.token });
      if (!m.token) { S.room = null; S.V = null; S.screen = 'home'; render(); }
      else if (m.code) history.replaceState(null, '', `/m/${m.code}`);
      return;
    case 'room': return onRoom(m);
    case 'error': return toast(m.text);
    case 'react': return showReact(m.id, m.text);
    case 'kicked': case 'left': case 'replaced':
      if (m.t === 'kicked') toast('El anfitrión te quitó de la mesa.');
      if (m.t === 'replaced') toast('Abriste esta mesa en otra pestaña.');
      S.token = null; store.set({ token: null }); S.room = null; S.V = null; S.screen = 'home';
      history.replaceState(null, '', '/');
      return render();
  }
}

function onRoom(m) {
  const prev = S.V;
  S.room = m; S.V = m.view;
  S.screen = m.started ? 'table' : 'room';
  const V = S.V;
  if (V) {
    for (const ev of m.ev || []) {
      if (ev.e === 'start') { UI.overlay = 'draw'; clearTimeout(UI.drawTimer); UI.drawTimer = setTimeout(() => { if (UI.overlay === 'draw') { UI.overlay = null; render(); } }, 6000); }
      if (ev.e === 'card') UI.callout = ev.callout ? { seat: ev.seat, text: ev.callout } : null;
      if (ev.e === 'trick') {
        UI.pausing = true; UI.sweeping = false; UI.shown = ev.trick; UI.winner = ev.seat;
        clearTimeout(UI.pauseTimer);
        UI.pauseTimer = setTimeout(sweep, TRICK_SHOW);
      }
      if (ev.e === 'next' || ev.e === 'start') { UI.shown = []; UI.winner = null; UI.callout = null; }
    }
    if (!UI.pausing) UI.shown = V.trick.slice();
    if (!prev || V.toAct !== V.mySeat || V.phase !== 'playing') UI.sel = null;
    if (V.phase !== 'bidding') UI.bid = null;
  } else {
    UI.overlay = null; UI.pausing = false; UI.shown = [];
  }
  render();
}

function sweep() {
  UI.sweeping = true; render();
  UI.pauseTimer = setTimeout(() => {
    UI.pausing = false; UI.sweeping = false; UI.winner = null; UI.callout = null;
    UI.shown = S.V ? S.V.trick.slice() : [];
    render();
  }, SWEEP);
}

// ─────────────────────────── Helpers ───────────────────────────
const esc = s => String(s).replace(/[&<>"']/g, ch => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[ch]);
const neg = v => (v < 0 ? '−' + -v : String(v));
const signed = v => (v > 0 ? '+' + v : '−' + -v);
const handSize = V => V.schedule[V.round];
const seatInfo = id => S.room?.seats.find(s => s.id === id) || {};
const myTurn = () => { const V = S.V; return !!V && V.toAct === V.mySeat && !UI.pausing && ACTIVE.includes(V.phase); };
const nameOf = (V, s) => (s === V.mySeat ? 'Tú' : V.players[s].name);
let toastTimer;
function toast(text) {
  toastEl.textContent = text; toastEl.hidden = false;
  clearTimeout(toastTimer); toastTimer = setTimeout(() => { toastEl.hidden = true; }, 3200);
}
function avatarHTML(p, cls = '', extra = '') {
  const [bg, fg] = COLORS[(p.color ?? 0) % COLORS.length];
  return `<div class="avatar ${cls}" style="background:${bg};color:${fg};${extra}">${esc((p.name || '?').charAt(0).toUpperCase())}</div>`;
}
const faceHTML = c => `<span class="ix"><b>${rsym(c.r)}</b><span>${GLYPH[c.s]}</span></span><span class="pip">${GLYPH[c.s]}</span>`;
const staticCard = (c, style = '') => `<div class="card ${isRed(c.s) ? 'r' : 'k'}" style="${style}" aria-label="${rsym(c.r)} de ${SUIT_NAME[c.s]}">${faceHTML(c)}</div>`;
function cardEl(c, tag = 'div') {
  const el = document.createElement(tag);
  el.className = 'card ' + (isRed(c.s) ? 'r' : 'k');
  el.innerHTML = faceHTML(c);
  el.setAttribute('aria-label', `${rsym(c.r)} de ${SUIT_NAME[c.s]}`);
  return el;
}
function chipsHTML(bid, took, playing) {
  if (bid == null) return `<span class="dark-pill" style="opacity:.6">…</span>`;
  const k = Math.min(Math.max(bid, took), 8);
  const chips = Array.from({ length: k }, (_, i) => `<i class="chip ${!playing || i < took ? 'on' : ''}"></i>`).join('');
  const label = playing ? `${took} de ${bid}` : bid === 0 ? 'Pasó' : `Pidió ${bid}`;
  return `<span class="dark-pill">${label}${k ? `<span class="chips">${chips}</span>` : ''}</span>`;
}
function sortHand(hand, ts) {
  const order = ['S', 'D', 'C', 'H'].filter(s => s !== ts).concat(ts ? [ts] : []);
  return [...hand].sort((a, b) => order.indexOf(a.s) - order.indexOf(b.s) || a.r - b.r);
}
function presenceHTML(id) {
  const s = seatInfo(id);
  if (s.bot) return `<span class="presence" title="Computadora">compu</span>`;
  if (s.covered) return `<span class="presence off" title="Juega la compu por ahora">compu</span>`;
  if (s.connected === false) return `<span class="presence off" title="Sin conexión">sin señal</span>`;
  return '';
}
function shareLink() {
  const url = `${location.origin}/m/${S.room.code}`;
  const text = `¡Ven a jugar Barbudo! Mesa ${S.room.code}`;
  if (navigator.share) navigator.share({ title: 'Barbudo', text, url }).catch(() => {});
  else navigator.clipboard?.writeText(`${text}: ${url}`).then(() => toast('Enlace copiado. Pégalo en el chat de la familia.'), () => toast(url));
}

// ─────────────────────────── Screens ───────────────────────────
function render() {
  if (S.screen !== app.dataset.screen) { app.innerHTML = ''; app.dataset.screen = S.screen; }
  if (S.screen === 'home') renderHome();
  else if (S.screen === 'room') renderRoom();
  else renderTable();
}

const MASCOT = `<svg width="84" height="84" viewBox="0 0 92 92" aria-hidden="true">
<circle cx="46" cy="44" r="32" fill="#F6D2A8" stroke="#3B2A20" stroke-width="3.5"/>
<path d="M14 44 C14 70 28 86 46 86 C64 86 78 70 78 44 C70 56 60 60 46 60 C32 60 22 56 14 44 Z" fill="#6B3E26" stroke="#3B2A20" stroke-width="3.5" stroke-linejoin="round"/>
<path d="M30 55 C36 49 42 50 46 54 C50 50 56 49 62 55 C56 59 50 58 46 56 C42 58 36 59 30 55 Z" fill="#4A2A1A" stroke="#3B2A20" stroke-width="2.5" stroke-linejoin="round"/>
<circle cx="35" cy="38" r="3.6" fill="#3B2A20"/><circle cx="57" cy="38" r="3.6" fill="#3B2A20"/>
<circle cx="26" cy="47" r="4.5" fill="#E8927C" opacity=".7"/><circle cx="66" cy="47" r="4.5" fill="#E8927C" opacity=".7"/>
<path d="M18 30 C24 12 68 12 74 30 C62 22 30 22 18 30 Z" fill="#6B3E26" stroke="#3B2A20" stroke-width="3.5" stroke-linejoin="round"/></svg>`;

function renderHome() {
  if (app.querySelector('.home-card')) return;
  app.innerHTML = `<div class="lobby">
    ${MASCOT}<h1 class="logo">Barbudo</h1><span class="dark-pill" style="font-size:14px">El juego de cartas de la familia</span>
    <div class="spacer"></div>
    <div class="home-card">
      ${invitedCode ? `<div class="invited">Te invitaron a la mesa ${esc(invitedCode)}</div>` : ''}
      <div class="field"><label class="label" for="name">Tu nombre</label>
        <input id="name" maxlength="14" autocomplete="nickname" placeholder="Como te dicen en la familia" value="${esc(S.name)}"></div>
      ${invitedCode ? '' : `<button class="big-btn" data-act="create">Crear una mesa</button>
      <div class="or">o únete con el código</div>`}
      <div class="join-row"><input id="code" class="code-input" maxlength="5" autocomplete="off" autocapitalize="characters" spellcheck="false" aria-label="Código de la mesa" placeholder="KX7PQ" value="${esc(invitedCode || '')}">
        <button class="big-btn ${invitedCode ? '' : 'soft'}" data-act="join">Unirme</button></div>
      <button class="big-btn soft" data-act="solo">Practicar contra la compu</button>
    </div>
    <div class="spacer"></div>
    <div class="fine">3 a 6 jugadores · cada uno en su celular</div></div>`;
  const nameEl = app.querySelector('#name');
  nameEl.addEventListener('input', () => { S.name = nameEl.value.trim(); store.set({ name: S.name }); });
  app.querySelector('#code').addEventListener('keydown', e => { if (e.key === 'Enter') app.querySelector('[data-act="join"]').click(); });
}

function needName() {
  if (S.name) return false;
  toast('Primero escribe tu nombre.');
  app.querySelector('#name')?.focus();
  return true;
}

function renderRoom() {
  const R = S.room, isHost = R.hostId === R.you, host = R.seats.find(s => s.id === R.hostId);
  const k = R.seats.length, rounds = k >= 3 ? (Math.floor(52 / k) - 1 + k) : null;
  const around = R.seats.map((s, i) => {
    const t = Math.PI / 2 + (2 * Math.PI * i) / Math.max(k, 3);
    return avatarHTML(s, s.connected ? '' : 'gone', `left:${115 + 100 * Math.cos(t)}px;top:${115 + 100 * Math.sin(t)}px`);
  }).join('');
  const rows = R.seats.map(s => `<div class="seat-row">${avatarHTML(s, s.connected ? '' : 'gone')}
      <div class="who"><b>${esc(s.name)}${s.id === R.you ? ' (tú)' : ''}</b>
        <small>${s.bot ? 'Computadora' : s.id === R.hostId ? 'Anfitrión' : s.connected ? 'Listo' : 'Sin conexión'}</small></div>
      ${isHost && s.id !== R.you ? `<button class="x-btn" data-act="kick" data-id="${s.id}" aria-label="Quitar a ${esc(s.name)}">×</button>` : ''}</div>`).join('');
  const empties = Math.max(0, 3 - k);
  app.innerHTML = `<div class="lobby">
    <div class="room-head"><button class="chunky icon-btn" data-act="leave" aria-label="Salir de la mesa">
      <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.8" stroke-linecap="round" stroke-linejoin="round"><path d="M15 5l-7 7 7 7"/></svg></button>
      <span class="label">Código de la mesa</span><span style="width:46px"></span></div>
    <div class="code-tiles" aria-label="Código ${R.code}">${[...R.code].map(c => `<span>${c}</span>`).join('')}</div>
    <div class="round-table"><div class="top"></div><div class="mid">${k} a la<br>mesa</div>${around}</div>
    <div class="seat-list">${rows}${'<div class="seat-row empty-seat">Falta alguien</div>'.repeat(empties)}</div>
    <span class="dark-pill">${rounds ? `${rounds} rondas · hasta ${Math.floor(52 / k)} cartas` : 'Se necesitan 3 a 6 jugadores'}</span>
    <div class="spacer"></div>
    <div class="row-btns"><button class="big-btn soft" data-act="invite">Invitar</button>
      ${isHost ? `<button class="big-btn soft" data-act="addBot" ${k >= 6 ? 'disabled' : ''}>+ Compu</button>` : ''}</div>
    ${isHost ? `<button class="big-btn" data-act="start" style="max-width:380px;height:56px;font-size:21px" ${k < 3 ? 'disabled' : ''}>¡A jugar!</button>`
             : `<div class="waiting-note">Esperando que ${esc(host?.name || 'el anfitrión')} empiece…</div>`}
  </div>`;
}

// ─────────────────────────── Table ───────────────────────────
function layout() {
  const V = S.V, W = app.clientWidth, H = app.clientHeight;
  const N = V.players.length, mine = V.mySeat ?? 0, cx = W / 2, cy = H * 0.4;
  const rel = s => (s - mine + N) % N;
  const ang = k => ((180 - (180 * (k - 1)) / (N - 2)) * Math.PI) / 180;
  const rx = W / 2 - 58, ry = Math.max(cy - 150, 60);
  const pos = s => { const t = ang(rel(s)); return { x: cx + rx * Math.cos(t), y: cy - 14 - ry * Math.sin(t) }; };
  return {
    W, H, cx, cy, runnerH: H * 0.36, pos,
    trick: s => { const k = rel(s); if (!k) return { x: 0, y: 58 }; const t = ang(k); return { x: 58 * Math.cos(t), y: -52 * Math.sin(t) }; },
    bubble: s => { if (!rel(s)) return { x: cx, y: H - 215 }; const p = pos(s); return { x: Math.min(Math.max(p.x, 70), W - 70), y: p.y + 92 }; },
  };
}

function buildTable() {
  app.innerHTML = `<div class="table-root">
    <div class="runner"><i style="height:7px;background:var(--terra)"></i><i style="height:4px;background:var(--gold)"></i><i style="height:7px;background:var(--teal)"></i><i class="zz"></i><i style="flex:1;background:var(--runner)"></i><i class="zz b"></i><i style="height:7px;background:var(--teal)"></i><i style="height:4px;background:var(--gold)"></i><i style="height:7px;background:var(--terra)"></i></div>
    <div class="header">
      <button class="chunky icon-btn" data-act="menu" aria-label="Salir de la mesa"><svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round"><path d="M4 7h16M4 12h16M4 17h16"/></svg></button>
      <div class="chunky round-pill"></div>
      <button class="chunky icon-btn" data-act="scores" aria-label="Ver puntajes"><svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><rect x="5" y="3.5" width="14" height="17" rx="2"/><path d="M8.5 8.5h7M8.5 12h7M8.5 15.5h4"/></svg></button>
    </div>
    <div class="seats"></div><div class="center"></div><div class="trick"></div><div class="bubbles"></div>
    <div class="bottom"><div class="action"></div><div class="status"></div><div class="hand"></div></div>
    <div class="overlay"></div></div>`;
}

function hintText(V) {
  const who = V.players[V.toAct].name;
  switch (V.phase) {
    case 'cutting': return myTurn() ? 'Toca el mazo para cortar' : `${who} corta`;
    case 'bidding': return myTurn() ? 'Tu turno' : `Pide ${who}`;
    case 'playing': {
      if (!myTurn()) return UI.pausing ? '…' : `Juega ${who}`;
      if (!V.trick.length) return 'Tu salida';
      const led = V.trick[0].card.s;
      return V.myHand.some(c => c.s === led) ? `Sigue ${GLYPH[led]}` : `Sin ${GLYPH[led]}: tira cualquiera`;
    }
    case 'roundScored': return 'Fin de la ronda';
    default: return 'Fin del juego';
  }
}

function renderTable() {
  const V = S.V;
  if (!V) return;
  if (!app.querySelector('.table-root')) buildTable();
  const L = layout(), N = V.players.length, mine = V.mySeat, playing = V.phase === 'playing' || V.phase === 'roundScored';
  const h = handSize(V);
  app.querySelector('.round-pill').textContent = `Ronda ${V.round + 1} de ${V.schedule.length} · ${h} ${h === 1 ? 'carta' : 'cartas'}`;
  const runner = app.querySelector('.runner');
  runner.style.top = L.cy - L.runnerH / 2 + 'px'; runner.style.height = L.runnerH + 'px';

  // Opponents, clockwise from your left
  const seats = [];
  for (let k = 1; k < N; k++) {
    const s = (mine + k) % N, p = V.players[s], pos = L.pos(s), right = pos.x > L.W / 2, info = seatInfo(p.id);
    const turn = V.toAct === s && !UI.pausing && ACTIVE.includes(V.phase);
    seats.push(`<div class="seat" style="left:${pos.x}px;top:${pos.y}px">
      <div style="position:relative">${avatarHTML(p, (turn ? 'turn ' : '') + (info.connected === false && !info.bot ? 'gone' : ''))}
        <div class="miniback back" style="${right ? 'left:-16px;transform:rotate(-12deg)' : 'right:-16px;transform:rotate(12deg)'}"><span>${V.handCounts[s]}</span></div>
        ${presenceHTML(p.id)}</div>
      <span class="pill">${esc(p.name)}${V.dealer === s ? ' <svg width="12" height="12" viewBox="0 0 24 24" aria-label="reparte"><rect x="4" y="3" width="13" height="17" rx="2" fill="var(--terra)" stroke="var(--ink)" stroke-width="2.5"/><rect x="8" y="6" width="13" height="16" rx="2" fill="var(--cream)" stroke="var(--ink)" stroke-width="2.5"/></svg>' : ''}</span>
      ${chipsHTML(V.bids[s], V.tricks[s], playing)}</div>`);
  }
  app.querySelector('.seats').innerHTML = seats.join('');

  // Middle of the table
  const center = app.querySelector('.center'), trickLayer = app.querySelector('.trick');
  if (V.phase === 'cutting' || V.phase === 'bidding') {
    trickLayer.innerHTML = '';
    const cuttable = V.phase === 'cutting' && myTurn();
    center.innerHTML = `<div class="deck ${cuttable ? 'cuttable' : ''}" style="left:${L.cx}px;top:${L.cy}px" ${cuttable ? 'role="button" tabindex="0" data-act="cut" aria-label="Cortar el mazo"' : ''}>
        ${V.trump ? staticCard(V.trump, 'left:34px;top:26px;transform:rotate(90deg)') : ''}
        <div class="card back ${cuttable ? 'top' : ''}" style="left:4px;top:18px;box-shadow:0 3px 0 var(--ink),0 6px 0 var(--cream),0 8px 0 var(--ink),0 11px 0 rgba(59,42,32,.3)"></div>
      </div>
      ${V.trump ? `<div style="position:absolute;left:${L.cx}px;top:${L.cy + 70}px;transform:translateX(-50%)">${trumpTag(V)}</div>` : ''}`;
  } else if (V.trump && ACTIVE.concat('roundScored').includes(V.phase)) {
    center.innerHTML = `<div style="position:absolute;left:16px;top:${L.cy + L.runnerH / 2 - 48}px">${trumpTag(V)}</div>`;
    renderTrick(L, trickLayer, V);
  } else { center.innerHTML = ''; trickLayer.innerHTML = ''; }

  // Speech bubbles: table talk + "¡Chancó!"
  const bubbles = [];
  if (UI.callout) { const p = L.bubble(UI.callout.seat); bubbles.push(`<div class="bubble" style="left:${p.x}px;top:${p.y}px">${UI.callout.text}</div>`); }
  for (const [id, text] of Object.entries(UI.reacts)) {
    const s = V.players.findIndex(p => p.id === id); if (s < 0) continue;
    const p = L.bubble(s);
    bubbles.push(`<div class="bubble react" style="left:${p.x}px;top:${p.y + (UI.callout?.seat === s ? 34 : 0)}px">${esc(text)}</div>`);
  }
  const bubbleHost = app.querySelector('.bubbles'), html = bubbles.join('');
  if (bubbleHost.dataset.sig !== html) { bubbleHost.innerHTML = html; bubbleHost.dataset.sig = html; }

  renderBottom(V);
  renderOverlay(V);
}

function trumpTag(V) {
  const holder = V.trumpHolder != null ? ` <span style="font-size:12px">· ${V.trumpHolder === V.mySeat ? 'la tienes tú' : 'la tiene ' + esc(V.players[V.trumpHolder].name)}</span>` : '';
  return `<span class="tag">Triunfo <span class="suit">${GLYPH[V.trump.s]}</span>${holder}</span>`;
}

function renderTrick(L, layer, V) {
  const keep = new Set(UI.shown.map(p => cid(p.card)));
  [...layer.querySelectorAll('.card')].forEach(el => { if (!keep.has(el.dataset.key)) el.remove(); });
  UI.shown.forEach(p => {
    const k = cid(p.card);
    let el = layer.querySelector(`[data-key="${k}"]`);
    if (!el) {
      el = cardEl(p.card); el.dataset.key = k; el.classList.add('enter');
      el.addEventListener('animationend', () => el.classList.remove('enter'), { once: true });
      layer.appendChild(el);
    }
    const o = L.trick(p.seat), rot = ((p.seat * 37) % 17) - 8;
    el.style.left = L.cx - 35 + o.x + 'px'; el.style.top = L.cy - 50 + o.y + 'px';
    el.classList.toggle('win', UI.winner === p.seat);
    if (UI.sweeping && UI.winner != null) {
      const wp = UI.winner === V.mySeat ? { x: L.cx, y: L.H - 60 } : L.pos(UI.winner);
      el.style.transform = `translate(${wp.x - L.cx - o.x}px, ${wp.y - L.cy - o.y}px) rotate(${rot}deg) scale(.35)`;
      el.style.opacity = '0';
    } else { el.style.transform = `rotate(${rot}deg)`; el.style.opacity = '1'; }
  });
  let note = layer.querySelector('.winner-note');
  if (UI.winner != null && !UI.sweeping) {
    if (!note) { note = document.createElement('div'); note.className = 'winner-note'; layer.appendChild(note); }
    note.textContent = UI.winner === V.mySeat ? '¡Te la llevas!' : `Se la lleva ${V.players[UI.winner].name}`;
    note.style.left = L.cx + 'px'; note.style.top = L.cy + 120 + 'px';
  } else if (note) note.remove();
}

function renderBottom(V) {
  const mine = V.mySeat, me = V.players[mine], playing = V.phase === 'playing' || V.phase === 'roundScored';
  const action = app.querySelector('.action'), turn = myTurn();

  if (V.phase === 'bidding' && turn) {
    const h = handSize(V), legal = V.legalBids, placed = V.bids.reduce((a, b) => a + (b || 0), 0);
    const forbidden = Array.from({ length: h + 1 }, (_, i) => i).find(b => !legal.includes(b));
    if (UI.bid == null || !legal.includes(UI.bid)) UI.bid = legal.reduce((best, b) => (Math.abs(b - h / 3) < Math.abs(best - h / 3) ? b : best));
    const cols = h + 1 <= 8 ? 4 : 6;
    const btns = Array.from({ length: h + 1 }, (_, b) => (b === forbidden
      ? `<button class="bid no" disabled aria-label="${b}, no permitido">${b}</button>`
      : `<button class="bid ${b === UI.bid ? 'on' : ''}" data-act="pick" data-n="${b}" aria-pressed="${b === UI.bid}">${b}</button>`)).join('');
    const key = `bid${V.round}`, existing = action.querySelector('.panel');
    const inner = `<div class="row"><h2>¿Cuántas te llevas?</h2><span class="count">Van ${placed} de ${h}</span></div>
      <div class="bids" style="grid-template-columns:repeat(${cols},minmax(0,1fr))">${btns}</div>
      ${forbidden != null ? `<div class="why">No puedes pedir ${forbidden}: sumaría ${h} y alguien tiene que fallar.</div>` : ''}
      <button class="big-btn" data-act="bid">${UI.bid === 0 ? 'Pasar' : 'Pedir ' + UI.bid}</button>`;
    if (existing && existing.dataset.k === key) existing.innerHTML = inner;
    else action.innerHTML = `<div class="panel" data-k="${key}">${inner}</div>`;
  } else if (V.phase === 'playing' && turn && UI.sel) {
    const c = V.myHand.find(x => cid(x) === UI.sel);
    action.innerHTML = c ? `<button class="big-btn throw" data-act="throw">Tirar ${rsym(c.r)}${GLYPH[c.s]}</button>` : '';
  } else if (UI.tray) {
    action.innerHTML = `<div class="tray">${PHRASES.map(p => `<button data-act="say" data-text="${esc(p)}">${esc(p)}</button>`).join('')}</div>`;
  } else action.innerHTML = '';

  app.querySelector('.status').innerHTML = `${avatarHTML(me, turn ? 'turn' : '')}
    <span class="pill">Tú${V.dealer === mine ? ' · reparte' : ''}</span>
    ${V.bids[mine] != null ? chipsHTML(V.bids[mine], V.tricks[mine], playing) : ''}
    <span class="hint ${turn ? 'me' : ''}">${hintText(V)}</span>
    <button class="chunky react-btn" data-act="tray" aria-label="Decir algo a la mesa" aria-expanded="${UI.tray}">
      <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linejoin="round"><path d="M4 5h16v11H9l-5 4z"/></svg></button>`;

  // Hand, keyed by card so cards glide rather than jump
  const handEl = app.querySelector('.hand');
  const cards = sortHand(V.myHand, V.trump?.s ?? null);
  const canPlay = V.phase === 'playing' && turn, legal = new Set(V.legalCards);
  const W = handEl.clientWidth, N = cards.length, mid = (N - 1) / 2;
  const step = N > 1 ? Math.min(46, (W - 70 - 24) / (N - 1)) : 0;
  const ang = N > 1 ? Math.min(5, 36 / Math.max(mid, 1)) : 0;
  const keep = new Set(cards.map(cid));
  [...handEl.children].forEach(el => { if (!keep.has(el.dataset.key)) el.remove(); });
  cards.forEach((c, i) => {
    const k = cid(c);
    let el = handEl.querySelector(`[data-key="${k}"]`);
    if (!el) {
      el = cardEl(c, 'button'); el.type = 'button'; el.dataset.key = k; el.dataset.act = 'card'; el.classList.add('enter');
      el.addEventListener('animationend', () => el.classList.remove('enter'), { once: true });
      handEl.appendChild(el);
    }
    const d = i - mid, isLegal = !canPlay || legal.has(k), sel = canPlay && UI.sel === k;
    const y = d * d * (N > 9 ? 1.2 : 3.2) + (sel ? -26 : 0) + (isLegal ? 0 : 10);
    el.style.left = W / 2 - 35 + 'px'; el.style.top = '8px'; el.style.zIndex = i;
    el.style.transform = `translate(${d * step}px, ${y}px) rotate(${d * ang}deg)`;
    el.classList.toggle('dim', !isLegal); el.classList.toggle('sel', sel); el.classList.toggle('idle', !canPlay);
    el.disabled = canPlay && !isLegal;
  });
}

// ─────────────────────────── Overlays ───────────────────────────
function renderOverlay(V) {
  const host = app.querySelector('.overlay');
  let html = '';
  if (UI.overlay === 'draw') html = drawHTML(V);
  else if (UI.overlay === 'scores') html = notepadHTML(V);
  else if (UI.overlay === 'menu') html = menuHTML();
  else if (V.phase === 'roundScored' && !UI.pausing) html = resultsHTML(V);
  else if (V.phase === 'gameOver') html = gameOverHTML(V);
  if (host.dataset.sig !== html) { host.innerHTML = html; host.dataset.sig = html; }
}
function drawHTML(V) {
  const first = V.players[0];
  return `<div class="scrim"><div class="sheet"><h2>Sacando cartas</h2>
    <div class="draws">${V.draws.map((d, i) => { const p = V.players.find(x => x.id === d.id);
      return `<div class="one ${i === 0 ? 'first' : ''}">${staticCard(d.card)}<span class="pill">${esc(p.id === V.players[V.mySeat].id ? 'Tú' : p.name)}</span></div>`; }).join('')}</div>
    <p class="why" style="text-align:center;margin:0">La carta más alta reparte primero. Se sientan en ese orden, en sentido horario.</p>
    <button class="big-btn" data-act="closeOverlay">${first.id === V.players[V.mySeat].id ? '¡Repartes tú!' : `Reparte ${esc(first.name)}`}</button></div></div>`;
}
function resultsHTML(V) {
  const d = V.scores[V.scores.length - 1], R = S.room, iAmReady = R.ready.includes(R.you);
  const rows = V.players.map((p, s) => {
    const info = seatInfo(p.id), auto = info.bot || info.covered;
    const status = auto ? '' : R.ready.includes(p.id) ? '<span class="ok">✓ listo</span>' : '<span class="wait">mirando…</span>';
    return `<div class="res">${avatarHTML(p)}
      <div><b>${esc(nameOf(V, s))}</b> ${status}<small>Pidió ${V.bids[s]} · se llevó ${V.tricks[s]}</small></div>
      <span class="d" style="color:${d[s] > 0 ? 'var(--gain)' : 'var(--loss)'}">${signed(d[s])}</span><span class="t">${neg(V.totals[s])}</span></div>`;
  }).join('');
  const last = V.round === V.schedule.length - 1;
  return `<div class="scrim"><div class="sheet"><h2>Fin de la ronda ${V.round + 1}</h2>${rows}
    <div class="btn-row"><button class="big-btn soft" data-act="scores">Hoja</button>
      <button class="big-btn" data-act="ready" ${iAmReady ? 'disabled' : ''}>${iAmReady ? 'Esperando…' : last ? 'Ver ganador' : 'Seguir'}</button></div></div></div>`;
}
function gameOverHTML(V) {
  const best = Math.max(...V.totals), win = V.players.map((p, s) => ({ p, s })).filter(x => V.totals[x.s] === best);
  const names = win.map(x => nameOf(V, x.s));
  const title = win.length > 1 ? '¡Empate!' : win[0].s === V.mySeat ? '¡Ganaste!' : `¡Ganó ${esc(names[0])}!`;
  const isHost = S.room.hostId === S.room.you;
  return `<div class="scrim"><div class="sheet" style="align-items:center">
    <div style="display:flex">${win.map(x => avatarHTML(x.p, '', 'width:72px;height:72px;font-size:32px;margin:0 -5px')).join('')}</div>
    <h2>${title}</h2><div class="why">${esc(names.join(' y '))} con ${best} puntos</div>
    <div class="btn-row" style="width:100%"><button class="big-btn soft" data-act="scores">Hoja</button>
      ${isHost ? '<button class="big-btn" data-act="rematch">Otra partida</button>' : '<button class="big-btn soft" data-act="leave" style="width:auto;flex:1">Salir</button>'}</div>
    ${isHost ? '' : '<div class="why">El anfitrión puede empezar otra partida.</div>'}</div></div>`;
}
function menuHTML() {
  return `<div class="scrim"><div class="sheet"><h2>Mesa ${esc(S.room.code)}</h2>
    <button class="big-btn soft" data-act="closeOverlay">Seguir jugando</button>
    <button class="big-btn" data-act="leave">Dejar la mesa</button>
    <div class="why" style="text-align:center">Si te vas, la compu juega por ti hasta el final.</div></div></div>`;
}
function notepadHTML(V) {
  const N = V.players.length, run = Array(N).fill(0), best = Math.max(...V.totals);
  const rows = V.scores.map((r, i) => {
    r.forEach((v, s) => { run[s] += v; });
    const last = i === V.scores.length - 1;
    return `<tr><td>${i + 1}</td>${run.map((tot, s) => `<td class="${last && tot === best ? 'lead' : ''}"><b>${neg(tot)}</b><em style="color:${r[s] > 0 ? 'var(--gain)' : 'var(--loss)'}">${signed(r[s])}</em></td>`).join('')}</tr>`;
  }).join('');
  const pending = V.phase === 'gameOver' ? '' : `<tr><td>${V.scores.length + 1}</td>${'<td style="color:var(--faint);font-size:22px">…</td>'.repeat(N)}</tr>`;
  const headColor = p => { const c = COLORS[p.color % COLORS.length][0]; return c === 'var(--gold)' ? '#8A6412' : c; };
  return `<div class="scrim"><div class="np-wrap"><div class="notepad"><div class="spiral">${'<i></i>'.repeat(6)}</div><div class="margin"></div>
    <div class="np-head"><b>Barbudo</b><span>ronda ${V.round + 1} de ${V.schedule.length}</span></div>
    <div class="np-scroll"><table class="np-table"><thead><tr><th>ronda</th>${V.players.map((p, s) => `<th style="color:${headColor(p)}">${esc(nameOf(V, s))}</th>`).join('')}</tr></thead>
    <tbody>${rows}${pending}</tbody></table></div>
    <div class="np-foot">exacto = +pedido · cero exacto = +1<br>corto = −pedido · pasado = −jugadas</div></div>
    <button class="big-btn np-close" data-act="closeOverlay">Volver a la mesa</button></div></div>`;
}

function showReact(id, text) {
  UI.reacts[id] = text; render();
  setTimeout(() => { if (UI.reacts[id] === text) { delete UI.reacts[id]; render(); } }, 2600);
}

// ─────────────────────────── Input ───────────────────────────
app.addEventListener('click', e => {
  const t = e.target.closest('[data-act]');
  if (!t || t.disabled) return;
  const V = S.V;
  switch (t.dataset.act) {
    case 'create': if (!needName()) send({ t: 'create', name: S.name }); break;
    case 'solo': if (!needName()) send({ t: 'create', name: S.name, solo: true }); break;
    case 'join': {
      if (needName()) break;
      const code = app.querySelector('#code').value.trim().toUpperCase();
      if (code.length !== 5) { toast('El código tiene 5 letras.'); break; }
      send({ t: 'join', code, name: S.name }); break;
    }
    case 'invite': shareLink(); break;
    case 'addBot': send({ t: 'addBot' }); break;
    case 'kick': send({ t: 'kick', id: t.dataset.id }); break;
    case 'start': send({ t: 'start' }); break;
    case 'leave':
      send({ t: 'leave' });
      S.token = null; store.set({ token: null }); S.room = null; S.V = null; S.screen = 'home'; UI.overlay = null;
      history.replaceState(null, '', '/'); render(); break;
    case 'menu': UI.overlay = 'menu'; render(); break;
    case 'cut': if (myTurn()) send({ t: 'cut', at: 8 + Math.floor(Math.random() * 37) }); break;
    case 'pick': UI.bid = +t.dataset.n; render(); break;
    case 'bid': if (myTurn()) send({ t: 'bid', n: UI.bid }); break;
    case 'card': {
      if (!(V?.phase === 'playing' && myTurn())) break;
      const k = t.dataset.key;
      if (!V.legalCards.includes(k)) break;
      if (UI.sel === k) { send({ t: 'play', card: k }); UI.sel = null; }
      else UI.sel = k;
      render(); break;
    }
    case 'throw': if (UI.sel && myTurn()) { send({ t: 'play', card: UI.sel }); UI.sel = null; render(); } break;
    case 'tray': UI.tray = !UI.tray; render(); break;
    case 'say': send({ t: 'react', text: t.dataset.text }); UI.tray = false; render(); break;
    case 'scores': UI.overlay = 'scores'; render(); break;
    case 'closeOverlay': UI.overlay = null; render(); break;
    case 'ready': send({ t: 'ready' }); break;
    case 'rematch': send({ t: 'rematch' }); break;
  }
});
app.addEventListener('keydown', e => {
  const t = e.target.closest('[data-act="cut"]');
  if (t && (e.key === 'Enter' || e.key === ' ')) { e.preventDefault(); t.click(); }
});
window.addEventListener('resize', () => { if (S.screen === 'table') render(); });

render();
connect();
