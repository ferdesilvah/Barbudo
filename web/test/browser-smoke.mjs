// Manual smoke test in real browsers (not part of `npm test`, needs Playwright):
//   PORT=8090 BOT_DELAY_MS=120 TRICK_PAUSE_MS=500 node server.js &
//   node test/browser-smoke.mjs
// Three relatives on phones + one bot: create, join by link, start, play several rounds.
import { chromium } from 'playwright';

const BASE = process.env.BASE || 'http://localhost:8090';
const browser = await chromium.launch({ executablePath: process.env.CHROMIUM || undefined });
const errors = [];
const phone = async name => {
  const ctx = await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 1 });
  const page = await ctx.newPage();
  page.on('pageerror', e => errors.push(`${name}: ${e.message}`));
  page.on('console', m => { if (m.type() === 'error' && !/fonts/.test(m.text())) errors.push(`${name}: ${m.text()}`); });
  page.name = name;
  return page;
};

const [ana, beto, caro] = await Promise.all(['Ana', 'Beto', 'Caro'].map(phone));
await ana.goto(BASE);
await ana.fill('#name', 'Ana');
await ana.click('[data-act="create"]');
await ana.waitForSelector('.code-tiles');
const code = (await ana.textContent('.code-tiles')).trim();
console.log('table', code);

for (const [p, n] of [[beto, 'Beto'], [caro, 'Caro']]) {
  await p.goto(`${BASE}/m/${code}`);              // invite link
  await p.fill('#name', n);
  await p.click('[data-act="join"]');
  await p.waitForSelector('.code-tiles');
}
await ana.waitForFunction(() => document.querySelectorAll('.seat-row').length === 3);
await ana.click('[data-act="addBot"]');
await ana.waitForFunction(() => document.querySelectorAll('.seat-row').length === 4);
await ana.screenshot({ path: process.env.SHOTS + '/room.png' });
await ana.click('[data-act="start"]');

// Each phone plays whatever is legal when it's their turn.
async function step(p) {
  return p.evaluate(() => {
    const q = s => document.querySelector(s);
    if (q('[data-act="closeOverlay"]') && q('.draws')) { q('[data-act="closeOverlay"]').click(); return 'draw'; }
    if (q('[data-act="ready"]:not([disabled])')) { q('[data-act="ready"]').click(); return 'ready'; }
    if (q('.deck.cuttable')) { q('.deck.cuttable').click(); return 'cut'; }
    if (q('.panel [data-act="bid"]')) { q('.panel [data-act="bid"]').click(); return 'bid'; }
    const card = [...document.querySelectorAll('.hand .card:not(.idle):not(.dim)')].pop();
    if (card) { card.click(); card.click(); return 'play'; }
    return null;
  });
}
let shotTaken = false;
const deadline = Date.now() + 90_000;
while (Date.now() < deadline) {
  for (const p of [ana, beto, caro]) {
    const did = await step(p);
    if (did === 'bid' && !shotTaken) { /* already clicked */ }
  }
  const round = await ana.evaluate(() => document.querySelector('.round-pill')?.textContent || '');
  if (!shotTaken && /Ronda 3 /.test(round)) {
    await beto.waitForTimeout(300);
    await beto.screenshot({ path: process.env.SHOTS + '/table.png' });
    shotTaken = true;
  }
  if (/Ronda 5 /.test(round)) break;
  await ana.waitForTimeout(120);
}
const final = await ana.evaluate(() => document.querySelector('.round-pill')?.textContent);
console.log('reached:', final);
console.log('errors:', errors.length ? errors : 'none');
await browser.close();
process.exit(errors.length || !/Ronda 5 /.test(final) ? 1 : 0);
