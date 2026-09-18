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
| `prototype-offline.html` | The earlier single-player prototype (no server). |

Settings (environment variables): `PORT`, `BOT_DELAY_MS` (850), `TRICK_PAUSE_MS` (1500),
`GRACE_MS` (45000), `ROUND_WAIT_MS` (30000), `DATA_FILE`.

House rules follow the defaults in the design doc: trump from the cut card in full-deal rounds,
trump may be led anytime, hook rule on the last bidder only.
