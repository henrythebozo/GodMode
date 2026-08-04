/**
 * Zero-dependency static server for GodMode Web (docs/).
 * Usage: npm run web   →  http://localhost:8741
 * Also listens on your LAN address so a phone on the same Wi-Fi can open it.
 */
const http = require('http');
const fs = require('fs');
const path = require('path');
const os = require('os');

const ROOT = path.join(__dirname, '..', '..', 'docs');
const PORT = process.env.PORT || 8741;

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
