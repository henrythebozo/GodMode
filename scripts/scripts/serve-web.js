/**
 * Zero-dependency static server for GodMode Web (docs/).
 * Usage: npm run web   →  http://localhost:8741
 * Also listens on your LAN address so a phone on the same Wi-Fi can open it.
 */
const http = require('http');
const https = require('https');
const fs = require('fs');
const path = require('path');
const os = require('os');

const ROOT = path.join(__dirname, '..', '..', 'docs');
const PORT = process.env.PORT || 8741;

// Pass-through API proxy so the browser can use vendors whose APIs block
// cross-origin requests (Kimi/Moonshot, Perplexity). The browser sends its
// own Authorization header; no keys are stored or logged here.
const PROXY_HOSTS = {
	moonshot: 'api.moonshot.ai',
	perplexity: 'api.perplexity.ai',
	anthropic: 'api.anthropic.com',
};
const DROP_HEADERS = ['host', 'origin', 'referer', 'connection'];

function proxy(req, res, vendor, upstreamPath) {
	const headers = {};
	for (const [k, v] of Object.entries(req.headers)) {
		if (!DROP_HEADERS.includes(k.toLowerCase())) headers[k] = v;
	}
	const up = https.request(
		{ host: PROXY_HOSTS[vendor], path: upstreamPath, method: req.method, headers },
		(upRes) => {
			res.writeHead(upRes.statusCode, upRes.headers);
			upRes.pipe(res);
		},
	);
	up.on('error', (e) => {
		res.writeHead(502, { 'Content-Type': 'application/json' });
		res.end(JSON.stringify({ error: { message: 'proxy error: ' + e.message } }));
	});
	req.pipe(up);
}

const MIME = {
	'.html': 'text/html; charset=utf-8',
	'.png': 'image/png',
	'.webmanifest': 'application/manifest+json',
	'.json': 'application/json',
	'.js': 'text/javascript',
	'.css': 'text/css',
	'.svg': 'image/svg+xml',
	'.ico': 'image/x-icon',
};

const server = http.createServer((req, res) => {
	const urlPath = decodeURIComponent(req.url.split('?')[0]);
	if (urlPath === '/proxy/ping') {
		res.writeHead(200, { 'Content-Type': 'text/plain' });
		return res.end('pong');
	}
	const proxyMatch = urlPath.match(/^\/proxy\/(moonshot|perplexity|anthropic)(\/.*)$/);
	if (proxyMatch) return proxy(req, res, proxyMatch[1], proxyMatch[2]);
	let file = path.normalize(path.join(ROOT, urlPath === '/' ? 'index.html' : urlPath));
	if (!file.startsWith(ROOT)) {
		res.writeHead(403);
		return res.end('forbidden');
	}
	fs.readFile(file, (err, data) => {
		if (err) {
			res.writeHead(404);
			return res.end('not found');
		}
		res.writeHead(200, {
			'Content-Type': MIME[path.extname(file)] || 'application/octet-stream',
			'Cache-Control': 'no-cache',
		});
		res.end(data);
	});
});

server.listen(PORT, '0.0.0.0', () => {
	console.log('');
	console.log('  🐣 GodMode Web is running:');
	console.log('');
	console.log(`     This computer:  http://localhost:${PORT}`);
	for (const ifaces of Object.values(os.networkInterfaces())) {
		for (const iface of ifaces || []) {
			if (iface.family === 'IPv4' && !iface.internal) {
				console.log(`     Phone on Wi-Fi: http://${iface.address}:${PORT}`);
			}
		}
	}
	console.log('');
	console.log('  Ctrl+C to stop.');
});
