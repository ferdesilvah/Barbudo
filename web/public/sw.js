// Keeps a copy of the table's shell so it opens instantly.
//
// Render's free plan puts the server to sleep after ~15 minutes without visitors, and the next
// person to open the link waits about a minute while it wakes up. The catch: that wait happens on
// the request for index.html itself, so without a cached copy the browser only gets Render's own
// "service waking up" page — our loading screen has nothing to load from. Keeping the shell here
// flips that around: the page paints straight away and client.js explains what's going on while
// the server wakes.

const VERSION = 'barbudo-v2';
const SHELL = `${VERSION}-shell`;
const FONTS = `${VERSION}-fonts`;
const ASSETS = ['/index.html', '/style.css', '/online.css', '/client.js', '/icon.svg', '/manifest.webmanifest'];

// Render answers with its waking-up page — a normal 200 full of HTML — for anything that arrives
// while the service is asleep. Cache that over our shell and the family would get Render's page
// from then on, so every response is checked for being ours before it's kept.
async function ours(res, req) {
  if (res.type === 'opaque') return true;                     // cross-origin fonts; nothing to read
  const type = res.headers.get('content-type') || '';
  const path = new URL(req.url).pathname;
  if (path.endsWith('.js')) return type.includes('javascript');
  if (path.endsWith('.css')) return type.includes('css');
  if (path.endsWith('.svg')) return type.includes('svg');
  if (path.endsWith('.webmanifest')) return type.includes('json') || type.includes('manifest');
  if (path === '/' || path.endsWith('.html')) {
    return type.includes('html') && (await res.text()).includes('id="boot"');
  }
  return true;
}

function keep(cacheName, req, res) {
  const forCheck = res.clone(), forCache = res.clone();
  ours(forCheck, req)
    .then(ok => (ok ? caches.open(cacheName).then(c => c.put(req, forCache)) : null))
    .catch(() => {});
}

// Always ask the network too, so a deploy lands on the next visit at the latest.
function revalidate(cacheName, req) {
  return fetch(req).then(res => {
    if (res && (res.ok || res.type === 'opaque')) keep(cacheName, req, res);
    return res;
  });
}

self.addEventListener('install', e => {
  // Each file on its own: a partial shell still beats Render's page.
  e.waitUntil(Promise.all(ASSETS.map(u => revalidate(SHELL, new Request(u)).catch(() => {})))
    .then(() => self.skipWaiting()));
});

self.addEventListener('activate', e => {
  e.waitUntil((async () => {
    const keys = await caches.keys();
    await Promise.all(keys.filter(k => k !== SHELL && k !== FONTS).map(k => caches.delete(k)));
    await self.clients.claim();
  })());
});

self.addEventListener('fetch', e => {
  const req = e.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);

  // /healthz is how the client checks whether the server is awake — it must never be answered
  // from a cache, or we'd think a sleeping server was up.
  if (url.origin === location.origin && (url.pathname === '/healthz' || url.pathname === '/ws')) return;

  // Fonts come from Google, which is awake even when our server isn't.
  if (url.hostname === 'fonts.googleapis.com' || url.hostname === 'fonts.gstatic.com') {
    e.respondWith(caches.match(req).then(hit => hit || revalidate(FONTS, req).catch(() => hit)));
    return;
  }
  if (url.origin !== location.origin) return;

  // Every way in — "/" and the /m/CODE invite links — is the same shell.
  if (req.mode === 'navigate') {
    e.respondWith((async () => {
      const cached = await caches.match('/index.html');
      if (!cached) return fetch(req);
      revalidate(SHELL, new Request('/index.html')).catch(() => {});
      return cached;
    })());
    return;
  }

  e.respondWith((async () => {
    const cached = await caches.match(req);
    if (!cached) return revalidate(SHELL, req);
    revalidate(SHELL, req).catch(() => {});
    return cached;
  })());
});
