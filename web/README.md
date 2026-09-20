# Barbudo — en línea

Barbudo, the family card game, played together in the browser. Each person uses their own
phone; no App Store, no accounts. One person creates a table and sends the link to the family chat.

## Try it on your computer

```
cd web
npm install
npm start            # → http://localhost:8080
```

Open it in two or three browser windows (or a normal + a private window) to play against yourself.
Phones on the same Wi-Fi can join at `http://<your-computer's-IP>:8080`.

`npm test` runs the rules simulations and full multiplayer games over real WebSockets.

## Put it online (free)

Pick one; each takes about 10 minutes and gives you an `https://…` link that works on any phone.

**Render** (simplest)
1. Push this repo to GitHub.
2. render.com › New › Blueprint › choose the repo. It reads `render.yaml` at the repo root.
3. Share `https://barbudo-xxxx.onrender.com` with the family.

The free plan sleeps after ~15 minutes without visitors; the first person to open it waits about a
minute. Tables in progress survive only while the server is awake — fine for a family evening.

**Fly.io** (always-on, keeps tables across restarts): `fly launch` in `web/` (uses the `Dockerfile`),
then `fly volumes create data` and mount it at `/data`.

### Pages on a static host, game on Render

While Render is asleep it answers every request with *its* waking-up page, so the very first visit
from a phone shows Render's branding instead of ours — there's no app running yet to show anything
else. Putting the pages somewhere always awake fixes that: they're only files, and the server is
only WebSockets.

1. Cloudflare dashboard › Workers & Pages › Create › connect the GitHub repo.
2. Build command: empty. Deploy command: `npx wrangler deploy`. Root directory: `/`.
3. Share the Cloudflare link with the family instead of the Render one.

`wrangler.jsonc` at the repo root is what makes step 2 work — it points Cloudflare at `web/public`
and says to answer anything unmatched with the page, which is how invite links (`/m/KX7PQ`) resolve.
Without it the deploy fails with "Could not detect a directory containing static files". Nothing of
ours runs on Cloudflare; it only hands out the seven files.

Nothing else changes: `client.js` sends the socket to `barbudo.onrender.com` whenever the page
isn't being served by the server itself, so `npm start`, a phone on your wifi and the Render URL
opened directly all still work untouched. Moving the game server elsewhere means editing
`GAME_SERVER` at the top of `public/client.js`. Cloudflare Pages or Netlify instead of a Worker:
publish directory `web/public`, no build command — `public/_redirects` is there for them, since
they read it and Workers uses `not_found_handling` in `wrangler.jsonc` instead.

Tables still live in Render's memory, so the first table of the evening still waits for it to wake;
the difference is that the family now waits on our own screen, with the mascot and an explanation,
and the wait starts the moment they open the link rather than after Render's page.

## How to play online

1. **Crear una mesa** → you get a 5-letter code and an **Invitar** button (shares the link).
2. Relatives open the link, type their name, **Unirme**.
3. Short on people? **+ Compu** adds a computer player. 3–6 seats.
4. The host presses **¡A jugar!** Everyone draws for seats, then it's the real game.
5. Add it to the home screen (Share › Add to Home Screen) so it opens like an app.

If someone's phone locks or they lose signal, their seat waits 45 seconds, then the computer plays for
them until they come back. They rejoin by opening the same link on the same phone.

## How it works

| File | Role |
| --- | --- |
| `shared/engine.js` | Rules, scoring, bots. Pure JS twin of the Swift `BarbudoCore`; same tests. |
| `server.js` | Tables, seats, turn order, reconnection, bot cover, saves tables to `data/rooms.json`. The only place that sees every hand. |
| `public/client.js` | The cozy table. Draws what the server says *this* player may see; sends moves. |
| `public/style.css`, `online.css` | The look from the design canvas. |
| `public/index.html` | Also holds the waking screen — markup, styles and its little script inline, since on a cold start `client.js` is itself still on its way. |
| `public/sw.js` | Keeps a copy of the shell so the page opens instantly, and refuses to cache anything that doesn't look like Barbudo. |
| `public/_redirects` | Tells a static host to answer `/m/CODE` with the page. Render ignores it. |
| `prototype-offline.html` | The earlier single-player prototype (no server). |

Settings (environment variables): `PORT`, `BOT_DELAY_MS` (850), `TRICK_PAUSE_MS` (1500),
`GRACE_MS` (45000), `ROUND_WAIT_MS` (30000), `DATA_FILE`.

House rules follow the defaults in the design doc: trump from the cut card in full-deal rounds,
trump may be led anytime, hook rule on the last bidder only.
