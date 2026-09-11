// Mac Remote service worker: makes the app installable and keeps the shell available while the Mac or the
// relay is unreachable. API calls always go to the network; shell assets are network-first with a cached
// fallback on network failure, on a relay 5xx, or when the network takes longer than a few seconds.
const VERSION = 'mr-v5';
const SHELL = ['./', 'index.html', 'style.css', 'app.js', 'manifest.webmanifest', 'icon-192.png', 'icon-512.png', 'icon-180.png'];
const NETWORK_WAIT_MS = 4000;

self.addEventListener('install', (e) => {
	e.waitUntil(caches.open(VERSION).then((c) => c.addAll(SHELL)).then(() => self.skipWaiting()));
});
self.addEventListener('activate', (e) => {
	e.waitUntil(caches.keys().then((keys) => Promise.all(keys.filter((k) => k !== VERSION).map((k) => caches.delete(k)))).then(() => self.clients.claim()));
});
self.addEventListener('fetch', (e) => {
	const url = new URL(e.request.url);
	if (e.request.method !== 'GET' || url.origin !== location.origin || url.pathname.startsWith('/api/') || url.pathname.startsWith('/relay/')) return;
	const navigate = e.request.mode === 'navigate';
	e.respondWith((async () => {
		const cached = (await caches.match(e.request, { ignoreSearch: true })) || (navigate ? await caches.match('index.html') : null);
		const network = fetch(e.request).then(async (res) => {
			if (res.ok && res.type === 'basic') { const copy = res.clone(); (await caches.open(VERSION)).put(e.request, copy); return res; }
			// 502/503/504 from the relay means the Mac is unreachable: the cached app renders its own retrying panel.
			if (res.status >= 500 && cached) return cached;
			return res;
		});
		if (!cached) return network.catch(() => (navigate ? caches.match('index.html') : Response.error()));
		const timer = new Promise((resolve) => setTimeout(() => resolve(cached), NETWORK_WAIT_MS));
		return Promise.race([network.catch(() => cached), timer]);
	})());
});
