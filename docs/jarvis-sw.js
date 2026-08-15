/* Service worker for Jarvis.
 *
 * Jarvis is already local-first — memory, reminders, notes, transcripts and
 * devices all live in localStorage — so with the app shell cached, everything
 * except the AI/weather/smart-home calls keeps working with no connection.
 * Without this, "Add to Home Screen" produced a white screen offline.
 *
 * Strategy: network-first, cache as fallback. The app is one big HTML file
 * that changes often, so cache-first would strand people on a stale build;
 * network-first means you always get the current app when you're online and
 * the last-known-good one when you aren't.
 *
 * Bump CACHE when shipping a change you want to force-evict. Old caches are
 * deleted on activate.
 */
const CACHE = 'jarvis-v1';
const SHELL = [
	'jarvis.html',
	'jarvis-manifest.webmanifest',
	'icon-180.png',
	'icon-512.png',
];

self.addEventListener('install', (event) => {
	event.waitUntil(
		caches.open(CACHE)
			// addAll fails the whole install if any single file 404s; cache them
			// individually so one missing icon can't break offline support entirely.
			.then((cache) => Promise.all(SHELL.map((url) => cache.add(url).catch(() => {}))))
			.then(() => self.skipWaiting()),
	);
});

self.addEventListener('activate', (event) => {
	event.waitUntil(
		caches.keys()
			.then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k))))
			.then(() => self.clients.claim()),
	);
});

self.addEventListener('fetch', (event) => {
	const req = event.request;
	// Only ever touch same-origin GETs. Every API call Jarvis makes (the AI
	// provider, Open-Meteo, Home Assistant, Higgsfield) is cross-origin, and
	// caching or replaying those would be wrong — and in the AI providers'
	// case would mean writing request bodies containing the user's prompts
	// into a cache they never asked for.
	if (req.method !== 'GET' || new URL(req.url).origin !== self.location.origin) return;

	event.respondWith(
		fetch(req)
			.then((res) => {
				// Only cache real, complete responses — not opaque or error ones.
				if (res && res.ok && res.type === 'basic') {
					const copy = res.clone();
					caches.open(CACHE).then((cache) => cache.put(req, copy)).catch(() => {});
				}
				return res;
			})
			.catch(() =>
				caches.match(req).then((hit) =>
					hit ||
					// A navigation with nothing cached for that exact URL still
					// shouldn't white-screen — fall back to the app shell.
					(req.mode === 'navigate' ? caches.match('jarvis.html') : undefined) ||
					Response.error(),
				),
			),
	);
});
