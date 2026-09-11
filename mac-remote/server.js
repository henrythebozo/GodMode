#!/usr/bin/env node
'use strict';
// Mac Remote — control a Mac from a phone browser. Zero dependencies (Node 18+).
//
//   node server.js            start (creates ~/.mac-remote/config.json + token on first run)
//   node server.js --init     only create the config and print the token
//   node server.js --token    print the current token
//   node server.js --rotate   generate a new token (logs every phone out)
//   node server.js --relay wss://your-relay.example.com <relay secret>
//                             dial out to your self-hosted relay (relay/relay.js) so the phone
//                             can reach the Mac from anywhere without port forwarding
//   node server.js --no-relay stop using the relay

const http = require('node:http');
const https = require('node:https');
const fs = require('node:fs');
const fsp = require('node:fs/promises');
const path = require('node:path');
const os = require('node:os');
const crypto = require('node:crypto');
const mac = require('./lib/mac');
const ws = require('./lib/ws');

const CONFIG_DIR = process.env.MAC_REMOTE_HOME || path.join(os.homedir(), '.mac-remote');
const CONFIG_FILE = path.join(CONFIG_DIR, 'config.json');
const PUBLIC_DIR = path.join(__dirname, 'public');
const SESSION_TTL_MS = 30 * 24 * 3600 * 1000;
const JSON_LIMIT = 256 * 1024;
const UPLOAD_LIMIT = 500 * 1024 * 1024;

// ---------------------------------------------------------------- config
function loadConfig() {
	fs.mkdirSync(CONFIG_DIR, { recursive: true, mode: 0o700 });
	let cfg = {};
	try { cfg = JSON.parse(fs.readFileSync(CONFIG_FILE, 'utf8')); } catch {}
	let dirty = false;
	if (!cfg.token || cfg.token.length < 20) { cfg.token = crypto.randomBytes(24).toString('base64url'); dirty = true; }
	cfg.port ??= 7331;
	cfg.host ??= '0.0.0.0';
	cfg.filesRoot ??= os.homedir();
	cfg.allowShell ??= true;
	cfg.allowPowerOff ??= true;
	cfg.tls ??= null; // { cert: "/path/fullchain.pem", key: "/path/privkey.pem" }
	cfg.relay ??= null; // { url: "wss://your-relay.fly.dev", secret: "..." }
	if (dirty || !fs.existsSync(CONFIG_FILE)) {
		fs.writeFileSync(CONFIG_FILE, JSON.stringify(cfg, null, 2) + '\n', { mode: 0o600 });
	}
	return cfg;
}

const argv = process.argv.slice(2);
const cfg = loadConfig();
if (argv.includes('--rotate')) {
	cfg.token = crypto.randomBytes(24).toString('base64url');
	fs.writeFileSync(CONFIG_FILE, JSON.stringify(cfg, null, 2) + '\n', { mode: 0o600 });
	try { fs.unlinkSync(path.join(CONFIG_DIR, 'sessions.json')); } catch {}
	console.log('New token:', cfg.token);
	process.exit(0);
}
if (argv.includes('--relay')) {
	const i = argv.indexOf('--relay');
	const url = argv[i + 1], secret = argv[i + 2];
	if (!url || !secret || !/^(wss?|https?):\/\//.test(url)) { console.error('Usage: node server.js --relay wss://your-relay.example.com <relay secret>'); process.exit(2); }
	cfg.relay = { url: url.replace(/^http/, 'ws').replace(/\/+$/, ''), secret };
	fs.writeFileSync(CONFIG_FILE, JSON.stringify(cfg, null, 2) + '\n', { mode: 0o600 });
	console.log(`Relay saved: ${cfg.relay.url}\nRestart the server to connect (launchctl kickstart -k gui/$(id -u)/com.macremote.agent).`);
	process.exit(0);
}
if (argv.includes('--no-relay')) {
	cfg.relay = null;
	fs.writeFileSync(CONFIG_FILE, JSON.stringify(cfg, null, 2) + '\n', { mode: 0o600 });
	console.log('Relay removed. Restart the server.');
	process.exit(0);
}
if (argv.includes('--init') || argv.includes('--token')) {
	console.log(`Config: ${CONFIG_FILE}`);
	console.log(`Token:  ${cfg.token}`);
	process.exit(0);
}

// ---------------------------------------------------------------- sessions
const SESSIONS_FILE = path.join(CONFIG_DIR, 'sessions.json');
const sessions = new Map(); // id -> { created, last, ua }
try {
	for (const [id, s] of Object.entries(JSON.parse(fs.readFileSync(SESSIONS_FILE, 'utf8')))) {
		if (Date.now() - s.last < SESSION_TTL_MS) sessions.set(id, s);
	}
} catch {}
let saveTimer = null;
function saveSessions() {
	clearTimeout(saveTimer);
	saveTimer = setTimeout(() => {
		fs.writeFile(SESSIONS_FILE, JSON.stringify(Object.fromEntries(sessions)), { mode: 0o600 }, () => {});
	}, 500);
}

function safeEqual(a, b) {
	const ab = Buffer.from(String(a)), bb = Buffer.from(String(b));
	return ab.length === bb.length && crypto.timingSafeEqual(ab, bb);
}

// Brute-force protection: 5 bad tokens per IP, then a 10 minute lock.
const failures = new Map();
function loginAllowed(ip) {
	const f = failures.get(ip);
	return !f || f.count < 5 || Date.now() - f.at > 10 * 60 * 1000;
}
function noteFailure(ip) {
	const now = Date.now();
	if (failures.size > 500) for (const [k, v] of failures) if (now - v.at > 10 * 60 * 1000 || failures.size > 1000) failures.delete(k);
	const f = failures.get(ip);
	if (f && now - f.at < 10 * 60 * 1000) { f.count++; f.at = now; } else failures.set(ip, { count: 1, at: now });
}

function isLoopback(addr) { return addr === '127.0.0.1' || addr === '::1' || addr === '::ffff:127.0.0.1'; }
function clientIp(req) {
	const xff = req.headers['x-forwarded-for'];
	if (xff && req.headers['x-relayed'] === '1' && isLoopback(req.socket.remoteAddress)) return String(xff).split(',')[0].trim();
	return req.socket.remoteAddress;
}

function parseCookies(req) {
	const out = {};
	for (const part of (req.headers.cookie || '').split(';')) {
		const i = part.indexOf('=');
		if (i > 0) out[part.slice(0, i).trim()] = decodeURIComponent(part.slice(i + 1).trim());
	}
	return out;
}

function authenticate(req) {
	const auth = req.headers.authorization || '';
	if (auth.startsWith('Bearer ') && safeEqual(auth.slice(7).trim(), cfg.token)) return { via: 'bearer' };
	const sid = parseCookies(req).mr_session;
	if (sid && sessions.has(sid)) {
		const s = sessions.get(sid);
		if (Date.now() - s.last > SESSION_TTL_MS) { sessions.delete(sid); saveSessions(); return null; }
		if (Date.now() - s.last > 60 * 1000) { s.last = Date.now(); saveSessions(); }
		return { via: 'cookie', sid };
	}
	return null;
}

// ---------------------------------------------------------------- http helpers
class HttpError extends Error { constructor(status, message) { super(message); this.status = status; } }

function send(res, status, body, headers = {}) {
	const isBuf = Buffer.isBuffer(body);
	const data = isBuf ? body : typeof body === 'string' ? body : JSON.stringify(body);
	res.writeHead(status, {
		'Content-Type': isBuf ? headers['Content-Type'] || 'application/octet-stream' : typeof body === 'string' ? 'text/plain; charset=utf-8' : 'application/json; charset=utf-8',
		'Content-Length': Buffer.byteLength(data),
		'Cache-Control': 'no-store',
		...headers,
	});
	res.end(data);
}

function readBody(req, limit) {
	return new Promise((resolve, reject) => {
		const chunks = [];
		let size = 0;
		req.on('data', (c) => {
			size += c.length;
			if (size > limit) { reject(new HttpError(413, 'Body too large')); req.destroy(); return; }
			chunks.push(c);
		});
		req.on('end', () => resolve(Buffer.concat(chunks)));
		req.on('error', reject);
	});
}

async function readJson(req) {
	const buf = await readBody(req, JSON_LIMIT);
	if (!buf.length) return {};
	try { return JSON.parse(buf.toString('utf8')); } catch { throw new HttpError(400, 'Invalid JSON'); }
}

function num(v, name, { min = -Infinity, max = Infinity } = {}) {
	const n = Number(v);
	if (!Number.isFinite(n)) throw new HttpError(400, `${name} must be a number`);
	return Math.min(max, Math.max(min, n));
}

// Normalized 0..1 coordinates from the phone → logical screen points.
async function toScreen(body, xKey = 'x', yKey = 'y') {
	const nx = num(body[xKey], xKey, { min: 0, max: 1 }), ny = num(body[yKey], yKey, { min: 0, max: 1 });
	const { w, h } = await mac.screenSize();
	return { x: nx * w, y: ny * h };
}

// Files API is confined to cfg.filesRoot.
function resolveFile(rel) {
	const root = path.resolve(cfg.filesRoot);
	const target = path.resolve(root, '.' + path.posix.normalize('/' + String(rel || '')));
	if (target !== root && !target.startsWith(root + path.sep)) throw new HttpError(403, 'Path outside allowed root');
	return target;
}

const MIME = {
	'.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.css': 'text/css; charset=utf-8',
	'.json': 'application/json', '.webmanifest': 'application/manifest+json', '.png': 'image/png', '.svg': 'image/svg+xml',
	'.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.gif': 'image/gif', '.pdf': 'application/pdf', '.txt': 'text/plain; charset=utf-8',
	'.mp4': 'video/mp4', '.mov': 'video/quicktime', '.mp3': 'audio/mpeg', '.m4a': 'audio/mp4', '.zip': 'application/zip', '.ico': 'image/x-icon',
};

function streamFile(req, res, file, stat, download) {
	const type = MIME[path.extname(file).toLowerCase()] || 'application/octet-stream';
	const headers = { 'Content-Type': type, 'Cache-Control': 'no-store', 'Accept-Ranges': 'bytes' };
	if (download) headers['Content-Disposition'] = `attachment; filename*=UTF-8''${encodeURIComponent(path.basename(file))}`;
	const range = /^bytes=(\d*)-(\d*)$/.exec(req.headers.range || '');
	if (range && stat.size) {
		const start = range[1] ? parseInt(range[1], 10) : 0;
		const end = range[2] ? Math.min(parseInt(range[2], 10), stat.size - 1) : stat.size - 1;
		if (start > end || start >= stat.size) { res.writeHead(416, { 'Content-Range': `bytes */${stat.size}` }); return res.end(); }
		res.writeHead(206, { ...headers, 'Content-Range': `bytes ${start}-${end}/${stat.size}`, 'Content-Length': end - start + 1 });
		return fs.createReadStream(file, { start, end }).pipe(res);
	}
	res.writeHead(200, { ...headers, 'Content-Length': stat.size });
	fs.createReadStream(file).pipe(res);
}

// ---------------------------------------------------------------- API
const api = {
	'GET /api/status': async () => ({ ...(await mac.systemStatus()), relay: relayState() }),

	'GET /api/screen.jpg': async (req, res, url) => {
		const w = Number(url.searchParams.get('w')) || 1280;
		const q = Number(url.searchParams.get('q')) || 60;
		const jpg = await mac.screenshot({ maxWidth: Math.min(3000, Math.max(200, w)), quality: Math.min(95, Math.max(10, q)) });
		send(res, 200, jpg, { 'Content-Type': 'image/jpeg' });
		return null;
	},

	'POST /api/mouse': async (req) => {
		const b = await readJson(req);
		switch (b.action) {
			case 'move': { const p = await toScreen(b); await mac.mouseMove(p.x, p.y); break; }
			case 'click': { const p = await toScreen(b); await mac.mouseClick(p.x, p.y); break; }
			case 'dblclick': { const p = await toScreen(b); await mac.mouseClick(p.x, p.y, { double: true }); break; }
			case 'rightclick': { const p = await toScreen(b); await mac.mouseClick(p.x, p.y, { button: 'right' }); break; }
			case 'drag': { const a = await toScreen(b), c = await toScreen(b, 'x2', 'y2'); await mac.mouseDrag(a.x, a.y, c.x, c.y); break; }
			case 'scroll': {
				if (b.x !== undefined && b.y !== undefined) { const p = await toScreen(b); await mac.mouseMove(p.x, p.y); }
				await mac.mouseScroll(num(b.dx ?? 0, 'dx'), num(b.dy ?? 0, 'dy'));
				break;
			}
			default: throw new HttpError(400, `Unknown mouse action: ${b.action}`);
		}
		return { ok: true };
	},

	'POST /api/key': async (req) => {
		const b = await readJson(req);
		if (!b.key) throw new HttpError(400, 'key required');
		await mac.pressKey(String(b.key), Array.isArray(b.mods) ? b.mods : []);
		return { ok: true };
	},
	'POST /api/type': async (req) => {
		const b = await readJson(req);
		if (typeof b.text !== 'string') throw new HttpError(400, 'text required');
		await mac.typeText(b.text.slice(0, 5000));
		return { ok: true };
	},

	'GET /api/volume': () => mac.getVolume(),
	'POST /api/volume': async (req) => {
		const b = await readJson(req);
		if (typeof b.muted === 'boolean') return mac.setMuted(b.muted);
		return mac.setVolume(num(b.level, 'level', { min: 0, max: 100 }));
	},
	'POST /api/media': async (req) => {
		const b = await readJson(req);
		await mac.mediaControl(String(b.action));
		return { ok: true, nowPlaying: await mac.nowPlaying().catch(() => null) };
	},

	'POST /api/power': async (req) => {
		const b = await readJson(req);
		if ((b.action === 'restart' || b.action === 'shutdown')) {
			if (!cfg.allowPowerOff) throw new HttpError(403, 'Restart/shutdown disabled in config');
			if (b.confirm !== true) throw new HttpError(400, 'confirm:true required');
		}
		await mac.power(String(b.action));
		return { ok: true };
	},

	'GET /api/apps': async () => ({ apps: await mac.runningApps(), front: await mac.frontmostApp() }),
	'POST /api/apps': async (req) => {
		const b = await readJson(req);
		const name = String(b.name || '').trim();
		if (!name) throw new HttpError(400, 'name required');
		if (b.action === 'open') await mac.openApp(name);
		else if (b.action === 'focus') await mac.focusApp(name);
		else if (b.action === 'quit') await mac.quitApp(name);
		else throw new HttpError(400, `Unknown app action: ${b.action}`);
		return { ok: true };
	},
	'POST /api/open': async (req) => {
		const b = await readJson(req);
		await mac.openUrl(String(b.url || ''));
		return { ok: true };
	},

	'GET /api/clipboard': async () => ({ text: await mac.clipboardGet() }),
	'POST /api/clipboard': async (req) => {
		const b = await readJson(req);
		await mac.clipboardSet(String(b.text ?? ''));
		return { ok: true };
	},

	'POST /api/say': async (req) => {
		const b = await readJson(req);
		if (!b.text) throw new HttpError(400, 'text required');
		mac.say(String(b.text).slice(0, 1000), b.voice ? String(b.voice) : undefined).catch(() => {});
		return { ok: true };
	},
	'POST /api/notify': async (req) => {
		const b = await readJson(req);
		await mac.notify(b.title, b.body);
		return { ok: true };
	},

	'POST /api/shell': async (req) => {
		if (!cfg.allowShell) throw new HttpError(403, 'Shell disabled in config');
		const b = await readJson(req);
		if (typeof b.cmd !== 'string' || !b.cmd.trim()) throw new HttpError(400, 'cmd required');
		return mac.shell(b.cmd, { cwd: b.cwd ? resolveFile(b.cwd) : undefined, timeout: Math.min(120000, num(b.timeout ?? 30000, 'timeout', { min: 1000 })) });
	},

	'GET /api/files': async (req, res, url) => {
		const rel = url.searchParams.get('path') || '';
		const dir = resolveFile(rel);
		const entries = await fsp.readdir(dir, { withFileTypes: true });
		const items = await Promise.all(entries.filter((e) => !e.name.startsWith('.')).map(async (e) => {
			let st = null;
			try { st = await fsp.stat(path.join(dir, e.name)); } catch {}
			return { name: e.name, dir: e.isDirectory() || (e.isSymbolicLink() && st?.isDirectory()), size: st?.size ?? 0, mtime: st?.mtimeMs ?? 0 };
		}));
		items.sort((a, b) => (a.dir !== b.dir ? (a.dir ? -1 : 1) : a.name.localeCompare(b.name, undefined, { sensitivity: 'base' })));
		return { path: path.relative(path.resolve(cfg.filesRoot), dir).split(path.sep).join('/'), root: cfg.filesRoot, items };
	},
	'GET /api/files/download': async (req, res, url) => {
		const file = resolveFile(url.searchParams.get('path') || '');
		const st = await fsp.stat(file).catch(() => { throw new HttpError(404, 'Not found'); });
		if (st.isDirectory()) throw new HttpError(400, 'Is a directory');
		streamFile(req, res, file, st, url.searchParams.get('inline') !== '1');
		return null;
	},
	'POST /api/files/upload': async (req, res, url) => {
		const rel = url.searchParams.get('path') || '';
		const name = path.basename(url.searchParams.get('name') || 'upload.bin');
		const dir = resolveFile(rel);
		const target = path.join(dir, name);
		// Stream straight to disk (via a temp file) so a large upload never sits in memory.
		const tmp = path.join(dir, `.${name}.uploading-${process.pid}-${Date.now()}`);
		let size = 0;
		try {
			await new Promise((resolve, reject) => {
				const out = fs.createWriteStream(tmp, { mode: 0o644 });
				req.on('data', (c) => { size += c.length; if (size > UPLOAD_LIMIT) { req.destroy(); out.destroy(); reject(new HttpError(413, 'Upload too large')); } });
				req.on('error', reject);
				out.on('error', reject);
				out.on('finish', resolve);
				req.pipe(out);
			});
			await fsp.rename(tmp, target);
		} catch (e) {
			fsp.unlink(tmp).catch(() => {});
			throw e;
		}
		return { ok: true, path: path.relative(path.resolve(cfg.filesRoot), target), size };
	},
	'POST /api/files/mkdir': async (req) => {
		const b = await readJson(req);
		await fsp.mkdir(resolveFile(b.path), { recursive: true });
		return { ok: true };
	},
	'POST /api/files/delete': async (req) => {
		const b = await readJson(req);
		const target = resolveFile(b.path);
		if (target === path.resolve(cfg.filesRoot)) throw new HttpError(400, 'Refusing to delete root');
		await fsp.rm(target, { recursive: true });
		return { ok: true };
	},

	'POST /api/logout': async (req, res, url, auth) => {
		if (auth.sid) { sessions.delete(auth.sid); saveSessions(); }
		res.setHeader('Set-Cookie', 'mr_session=; Path=/; Max-Age=0; HttpOnly; SameSite=Strict');
		return { ok: true };
	},
	'GET /api/me': (req, res, url, auth) => ({ ok: true, via: auth.via, hostname: os.hostname(), sessions: sessions.size }),
};

async function handleLogin(req, res) {
	const ip = clientIp(req);
	if (!loginAllowed(ip)) throw new HttpError(429, 'Too many attempts. Wait 10 minutes.');
	const b = await readJson(req);
	if (!b.token || !safeEqual(String(b.token).trim(), cfg.token)) { noteFailure(ip); throw new HttpError(401, 'Wrong token'); }
	failures.delete(ip);
	const sid = crypto.randomBytes(32).toString('base64url');
	sessions.set(sid, { created: Date.now(), last: Date.now(), ua: String(req.headers['user-agent'] || '').slice(0, 200), ip });
	saveSessions();
	const secure = Boolean(cfg.tls) || req.headers['x-forwarded-proto'] === 'https';
	res.setHeader('Set-Cookie', `mr_session=${sid}; Path=/; Max-Age=${SESSION_TTL_MS / 1000}; HttpOnly; SameSite=Strict${secure ? '; Secure' : ''}`);
	return { ok: true, hostname: os.hostname() };
}

// Cookie-authenticated state changes must come from our own origin.
function checkOrigin(req) {
	const origin = req.headers.origin;
	if (!origin) return;
	let host;
	try { host = new URL(origin).host; } catch { throw new HttpError(403, 'Bad origin'); }
	const ours = req.headers['x-forwarded-host'] || req.headers.host;
	if (host !== ours) throw new HttpError(403, 'Cross-origin request blocked');
}

async function serveStatic(req, res, pathname) {
	let rel = pathname === '/' ? '/index.html' : pathname;
	const file = path.join(PUBLIC_DIR, path.normalize(rel));
	if (!file.startsWith(PUBLIC_DIR)) throw new HttpError(403, 'Forbidden');
	let st;
	try { st = await fsp.stat(file); } catch { throw new HttpError(404, 'Not found'); }
	if (st.isDirectory()) throw new HttpError(404, 'Not found');
	const type = MIME[path.extname(file).toLowerCase()] || 'application/octet-stream';
	res.writeHead(200, { 'Content-Type': type, 'Content-Length': st.size, 'Cache-Control': rel === '/index.html' ? 'no-cache' : 'public, max-age=3600' });
	fs.createReadStream(file).pipe(res);
}

async function handler(req, res) {
	const url = new URL(req.url, 'http://x');
	res.setHeader('X-Content-Type-Options', 'nosniff');
	res.setHeader('Referrer-Policy', 'no-referrer');
	res.setHeader('X-Frame-Options', 'DENY');
	try {
		if (req.method === 'POST' && url.pathname === '/api/login') { checkOrigin(req); return send(res, 200, await handleLogin(req, res)); }
		if (url.pathname.startsWith('/api/')) {
			const auth = authenticate(req);
			if (!auth) throw new HttpError(401, 'Not authenticated');
			if (req.method !== 'GET' && auth.via === 'cookie') checkOrigin(req);
			const fn = api[`${req.method} ${url.pathname}`];
			if (!fn) throw new HttpError(404, 'No such endpoint');
			const out = await fn(req, res, url, auth);
			if (out !== null && !res.headersSent) send(res, 200, out);
			return;
		}
		if (req.method !== 'GET' && req.method !== 'HEAD') throw new HttpError(405, 'Method not allowed');
		return await serveStatic(req, res, url.pathname);
	} catch (e) {
		const fsErr = e.syscall && !/^spawn/.test(e.syscall); // fs errors, not "spawn osascript ENOENT"
		if (fsErr && (e.code === 'ENOENT' || e.code === 'ENOTDIR')) { e.status = 404; e.message = 'Not found'; }
		if (fsErr && (e.code === 'EACCES' || e.code === 'EPERM')) { e.status = 403; e.message = 'Permission denied'; }
		const status = e.status || 500;
		if (status === 500) console.error(`[${new Date().toISOString()}] ${req.method} ${url.pathname}:`, e.message);
		if (!res.headersSent) send(res, status, { error: e.message || 'Server error' });
		else res.end();
	}
}

// ---------------------------------------------------------------- boot
let server;
if (cfg.tls && cfg.tls.cert && cfg.tls.key) {
	server = https.createServer({ cert: fs.readFileSync(cfg.tls.cert), key: fs.readFileSync(cfg.tls.key) }, handler);
} else {
	server = http.createServer(handler);
}
server.requestTimeout = 10 * 60 * 1000;

server.listen(cfg.port, cfg.host, () => {
	const proto = cfg.tls ? 'https' : 'http';
	const addrs = Object.values(os.networkInterfaces()).flat().filter((a) => a && a.family === 'IPv4' && !a.internal).map((a) => a.address);
	console.log(`Mac Remote listening on ${proto}://${cfg.host}:${cfg.port}`);
	for (const a of addrs) console.log(`  ${proto}://${a}:${cfg.port}`);
	console.log(`Token: ${cfg.token}   (config: ${CONFIG_FILE})`);
	printLoginHint(proto, addrs);
	if (!mac.IS_MAC) console.log('Warning: not running on macOS. Control endpoints will fail; UI and auth still work.');
	mac.findCliclick().then((cc) => { if (mac.IS_MAC && !cc) console.log('Tip: brew install cliclick   (more reliable mouse control)'); });
	if (cfg.relay && cfg.relay.url && cfg.relay.secret) {
		startLoopbackListener().then(relayLoop, (e) => console.error(`relay: could not open the loopback listener: ${e.message}`));
	}
});

// One-tap login: open this URL on the phone and the token in the fragment logs it in, then is scrubbed.
// If `qrencode` (brew install qrencode) is present, also draw it as a QR code.
function printLoginHint(proto, addrs) {
	const { execFile } = require('node:child_process');
	let url;
	if (cfg.relay) {
		url = `${cfg.relay.url.replace(/^ws/, 'http')}/#token=${cfg.token}`;
		console.log(`Relay: ${cfg.relay.url}  (works from anywhere once the relay shows the Mac as connected)`);
	} else {
		const ip = addrs.find((a) => a.startsWith('100.')) || addrs[0];
		if (!ip) return;
		url = `${proto}://${ip}:${cfg.port}/#token=${cfg.token}`;
	}
	console.log(`Login URL (keep private): ${url}`);
	execFile('qrencode', ['-t', 'ANSIUTF8', '-m', '1', url], (err, out) => {
		if (!err && out) console.log(out);
	});
}

// ---------------------------------------------------------------- relay client
// Dials out to relay/relay.js and serves every forwarded request by replaying it against
// this very server over loopback, so the relay path and the LAN path behave identically.
// Bodies are streamed both ways in chunks with an ack window (see relay/relay.js for the wire protocol).
const relay = { connected: false, since: null, lastError: null, attempts: 0 };
function relayState() { return cfg.relay ? { url: cfg.relay.url, ...relay } : null; }
const RELAY_WINDOW = 8;
const RELAY_MAX_MESSAGE = 4 * 1024 * 1024;

// Relayed requests are replayed against a plain-HTTP listener bound to 127.0.0.1 only, so the main
// listener may use TLS or bind to a single interface (e.g. a Tailscale IP) without affecting the relay.
let loopbackPort = null;
function startLoopbackListener() {
	return new Promise((resolve, reject) => {
		const l = http.createServer(handler);
		l.requestTimeout = server.requestTimeout;
		l.on('error', reject);
		l.listen(0, '127.0.0.1', () => { loopbackPort = l.address().port; resolve(loopbackPort); });
	});
}

function relaySession(conn) {
	const streams = new Map(); // id -> { req, res, inflight }
	const send = (h, body) => { if (conn.readyState === 1) conn.send(ws.pack(h, body)); };
	const drop = (id) => { const st = streams.get(id); if (!st) return; streams.delete(id); try { st.req.destroy(); } catch {} try { st.res?.destroy(); } catch {} };

	conn.on('message', (data, isBinary) => {
		if (!isBinary) return;
		let msg;
		try { msg = ws.unpack(data); } catch { return; }
		const h = msg.header;
		const st = streams.get(h.id);
		switch (h.t) {
			case 'req': {
				if (st) drop(h.id);
				const headers = {};
				for (const [k, v] of Object.entries(h.headers || {})) if (k !== 'transfer-encoding' && k !== 'connection' && k !== 'host') headers[k] = v;
				headers.host = `127.0.0.1:${loopbackPort}`;
				const entry = { req: null, res: null, inflight: 0 };
				entry.req = http.request({ host: '127.0.0.1', port: loopbackPort, method: h.method, path: h.url, headers }, (res) => {
					entry.res = res;
					send({ id: h.id, t: 'res', status: res.statusCode, headers: res.headers });
					res.on('data', (chunk) => {
						entry.inflight++;
						send({ id: h.id, t: 'data' }, chunk);
						if (entry.inflight >= RELAY_WINDOW) res.pause();
					});
					res.on('end', () => { streams.delete(h.id); send({ id: h.id, t: 'end' }); });
					res.on('error', (e) => { streams.delete(h.id); send({ id: h.id, t: 'err', message: e.message }); });
				});
				entry.req.on('error', (e) => { if (streams.get(h.id) === entry) { streams.delete(h.id); send({ id: h.id, t: 'err', message: e.message }); } });
				streams.set(h.id, entry);
				break;
			}
			case 'data': if (st) st.req.write(msg.body, () => send({ id: h.id, t: 'ack' })); break;
			case 'end': if (st) st.req.end(); break;
			case 'ack': if (st) { st.inflight = Math.max(0, st.inflight - 1); if (st.inflight < RELAY_WINDOW && st.res && st.res.isPaused()) st.res.resume(); } break;
			case 'abort': drop(h.id); break;
		}
	});
	conn.on('close', () => { for (const id of [...streams.keys()]) drop(id); });
}

async function relayLoop() {
	const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
	let backoff = 1000;
	for (;;) {
		let conn;
		relay.attempts++;
		try {
			conn = await ws.connect(`${cfg.relay.url}/agent/connect`, {
				headers: { Authorization: `Bearer ${cfg.relay.secret}`, 'X-Agent-Name': os.hostname().replace(/\.local$/, '') },
				maxMessage: RELAY_MAX_MESSAGE,
			});
		} catch (e) {
			relay.lastError = e.message;
			if (e.status === 401) console.error(`relay: rejected our secret (401). Fix it with: node server.js --relay ${cfg.relay.url} <secret>`);
			else if (relay.attempts === 1 || relay.attempts % 20 === 0) console.error(`relay: connect failed (${e.message}); retrying`);
			await sleep(backoff);
			backoff = Math.min(backoff * 2, 30000);
			continue;
		}
		relay.connected = true; relay.since = Date.now(); relay.lastError = null; backoff = 1000;
		console.log(`relay: connected to ${cfg.relay.url}`);
		let lastPong = Date.now();
		const hb = setInterval(() => {
			if (conn.readyState !== 1) return;
			if (Date.now() - lastPong > 60 * 1000) { console.error('relay: heartbeat timeout, reconnecting'); conn.terminate(); return; }
			conn.ping();
		}, 20 * 1000);
		conn.on('pong', () => { lastPong = Date.now(); });
		conn.on('ping', () => { lastPong = Date.now(); });
		conn.on('error', (e) => { relay.lastError = e.message; });
		relaySession(conn);
		await new Promise((resolve) => conn.on('close', (code, reason) => { clearInterval(hb); relay.connected = false; console.log(`relay: disconnected (${code} ${reason || ''}); reconnecting`); resolve(); }));
		await sleep(backoff);
	}
}

process.on('SIGTERM', () => { server.close(() => process.exit(0)); setTimeout(() => process.exit(0), 2000); });
process.on('SIGINT', () => process.exit(0));
