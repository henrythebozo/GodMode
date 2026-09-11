// Mac Remote service worker: makes the app installable and keeps the shell available
// while the Mac or relay is briefly unreachable. API calls always go to the network.
const VERSION = 'mr-v3';
const SHELL = ['./', 'index.html', 'style.css', 'app.js', 'manifest.webmanifest', 'icon-192.png', 'icon-512.png', 'icon-180.png'];

self.addEventListener('install', (e) => {
	e.waitUntil(caches.open(VERSION).then((c) => c.addAll(SHELL)).then(() => self.skipWaiting()));
});
self.addEventListener('activate', (e) => {
	e.waitUntil(caches.keys().then((keys) => Promise.all(keys.filter((k) => k !== VERSION).map((k) => caches.delete(k)))).then(() => self.clients.claim()));
});
self.addEventListener('fetch', (e) => {
	const url = new URL(e.request.url);
	if (e.request.method !== 'GET' || url.origin !== location.origin || url.pathname.startsWith('/api/') || url.pathname.startsWith('/relay/')) return;
	// Network first so updates land immediately; fall back to the cached shell when offline.
	// A 502/503/504 on a navigation is the relay saying the Mac is unreachable: show the cached
	// app instead (it renders its own retrying "unreachable" panel), so the home-screen app never
	// turns into a plain web page.
	const shell = () => caches.match(e.request, { ignoreSearch: true }).then((hit) => hit || caches.match('index.html'));
	e.respondWith(
		fetch(e.request).then((res) => {
			if (res.ok && res.type === 'basic') { const copy = res.clone(); caches.open(VERSION).then((c) => c.put(e.request, copy)); return res; }
			if (e.request.mode === 'navigate' && res.status >= 502 && res.status <= 504) return shell().then((hit) => hit || res);
			return res;
		}).catch(shell)
	);
});
