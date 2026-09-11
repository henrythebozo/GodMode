#!/usr/bin/env node
'use strict';
// Mac Remote relay. Runs on any public host. The Mac dials OUT to this relay over a
// WebSocket (so no port forwarding), and every HTTP request that reaches the relay
// is streamed through that socket to the Mac and the response streamed back.
//
//   RELAY_SECRET=<long random string> PORT=8080 node relay/relay.js
//
// Zero dependencies. Env:
//   RELAY_SECRET   required; the Mac must present it to register (Authorization: Bearer)
//   PORT           listen port (default 8080)
//   TRUST_PROXY    how to learn the phone's IP behind the TLS proxy in front of this relay (only used to key
//                  the Mac's login lockout, so a wrong value cannot let anyone in):
//                    "1"      (default) last hop of X-Forwarded-For — right behind one proxy you run (Caddy, nginx)
//                    "fly"    Fly-Client-IP (Fly.io sets it; clients cannot spoof it)
//                    "render" True-Client-IP / CF-Connecting-IP, else the FIRST X-Forwarded-For entry (Render, Cloudflare)
//                    "0"      no proxy in front; the TCP peer address
//   CLIENT_IP_HEADER  name of a header your proxy sets to the real client IP; overrides TRUST_PROXY when present
//   MAX_PENDING    max concurrent in-flight requests (default 64)
//   MAX_BODY_MB    max request or response body streamed per request (default 512)
//
// Wire protocol (each WebSocket binary message = [uint32 header length][JSON header][chunk]):
//   relay → Mac : {id,t:'req',method,url,headers}   {id,t:'data'}+chunk*   {id,t:'end'}   {id,t:'ack'}   {id,t:'abort'}
//   Mac → relay : {id,t:'res',status,headers}       {id,t:'data'}+chunk*   {id,t:'end'}   {id,t:'ack'}   {id,t:'err',message}
// Bodies are streamed in chunks with a small ack window in each direction, so a 2 GB download
// never sits in memory on either side and a slow phone cannot inflate the relay.

const http = require('node:http');
const crypto = require('node:crypto');
const ws = require('../lib/ws');

const SECRET = process.env.RELAY_SECRET;
const PORT = Number(process.env.PORT) || 8080;
const TRUST_PROXY = String(process.env.TRUST_PROXY ?? '1').toLowerCase();
const MAX_PENDING = Number(process.env.MAX_PENDING) || 64;
const MAX_BODY = (Number(process.env.MAX_BODY_MB) || 512) * 1024 * 1024;
const MAX_MESSAGE = 4 * 1024 * 1024; // a single WebSocket message (one chunk + header)
const WINDOW = 8;                    // chunks in flight per request before waiting for acks
const HEAD_TIMEOUT_MS = 90 * 1000;   // time for the Mac to start answering
const IDLE_TIMEOUT_MS = 90 * 1000;   // time between body chunks
const PING_EVERY_MS = 25 * 1000;
const PONG_GRACE_MS = 15 * 1000;

if (!SECRET || SECRET.length < 16) {
	console.error('RELAY_SECRET must be set to a random string of at least 16 characters, e.g.\n  RELAY_SECRET=$(openssl rand -base64 24) node relay/relay.js');
	process.exit(1);
}

let agent = null; // { conn, name, since, pending: Map<id, entry>, seq, lastPong }
const startedAt = Date.now();
let served = 0;

function safeEqual(a, b) {
	const ab = Buffer.from(String(a)), bb = Buffer.from(String(b));
	return ab.length === bb.length && crypto.timingSafeEqual(ab, bb);
}
const log = (...a) => console.log(`[${new Date().toISOString()}]`, ...a);

// Hop-by-hop and relay-internal headers never cross the tunnel.
const STRIP_REQ = new Set(['connection', 'keep-alive', 'proxy-authenticate', 'proxy-authorization', 'te', 'trailer', 'transfer-encoding', 'upgrade', 'host', 'forwarded', 'fly-client-ip', 'true-client-ip', 'cf-connecting-ip', 'x-relayed', 'expect']);
const STRIP_RES = new Set(['connection', 'keep-alive', 'transfer-encoding', 'upgrade', 'trailer']);

const CLIENT_IP_HEADER = String(process.env.CLIENT_IP_HEADER || '').toLowerCase();
function clientIp(req) {
	const first = (v) => String(v).split(',')[0].trim();
	if (CLIENT_IP_HEADER && req.headers[CLIENT_IP_HEADER]) return first(req.headers[CLIENT_IP_HEADER]);
	const xff = String(req.headers['x-forwarded-for'] || '').split(',').map((s) => s.trim()).filter(Boolean);
	switch (TRUST_PROXY) {
		case 'fly':
			if (req.headers['fly-client-ip']) return first(req.headers['fly-client-ip']);
			return xff.length ? xff[xff.length - 1] : req.socket.remoteAddress;
		case 'render': case 'cloudflare': case 'first':
			if (req.headers['true-client-ip']) return first(req.headers['true-client-ip']);
			if (req.headers['cf-connecting-ip']) return first(req.headers['cf-connecting-ip']);
			return xff.length ? xff[0] : req.socket.remoteAddress;
		case '0': case 'false': case 'no':
			return req.socket.remoteAddress;
		default:
			// The LAST x-forwarded-for entry is the one appended by the proxy directly in front of us;
			// earlier entries are client-supplied and spoofable.
			return xff.length ? xff[xff.length - 1] : req.socket.remoteAddress;
	}
}
function clientProto(req) {
	if (!['0', 'false', 'no'].includes(TRUST_PROXY) && req.headers['x-forwarded-proto']) return String(req.headers['x-forwarded-proto']).split(',')[0].trim();
	return 'http';
}

const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
function statusPage(req, res, status, title, detail) {
	if (res.headersSent) { res.destroy(); return; }
	const wantsHtml = /text\/html/.test(req.headers.accept || '') && !req.url.startsWith('/api/');
	res.writeHead(status, { 'Content-Type': wantsHtml ? 'text/html; charset=utf-8' : 'application/json; charset=utf-8', 'Cache-Control': 'no-store', 'Retry-After': '5' });
	if (!wantsHtml) return res.end(JSON.stringify({ error: title, detail }));
	res.end(`<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover"><title>Mac Remote</title>
<style>body{margin:0;background:#000;color:#fff;font:16px/1.5 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;display:grid;place-items:center;min-height:100dvh;text-align:center;padding:24px;box-sizing:border-box}
.logo{width:72px;height:72px;border-radius:20px;background:linear-gradient(145deg,#a58bff,#5a3fd6);display:grid;place-items:center;margin:0 auto 16px}h1{font-size:22px;margin:0 0 8px}p{color:#8e8e93;margin:0 0 20px;max-width:320px}
a{display:inline-block;background:#7b5cf0;color:#fff;text-decoration:none;padding:12px 22px;border-radius:12px;font-weight:500}</style></head>
<body><div><div class="logo"><svg width="38" height="38" viewBox="0 0 24 24" fill="none" stroke="#fff" stroke-width="2.2" stroke-linecap="round"><path d="M12 3v9"/><path d="M6.3 6.3a8 8 0 1 0 11.4 0"/></svg></div>
<h1>${esc(title)}</h1><p>${esc(detail)}</p><a href="#" onclick="location.reload();return false">Try again</a></div>
<script>setTimeout(()=>location.reload(),8000)</script></body></html>`);
}

// ---------------------------------------------------------------- phone → relay
const server = http.createServer((req, res) => {
	const path = req.url.split('?')[0];
	if (path === '/relay/health') { res.writeHead(200, { 'Content-Type': 'text/plain' }); return res.end('ok'); }
	if (path === '/relay/status') {
		res.writeHead(200, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' });
		return res.end(JSON.stringify({ agent: agent ? { connected: true, since: agent.since, pending: agent.pending.size } : null, uptime: Math.round((Date.now() - startedAt) / 1000), served }));
	}
	if (path.startsWith('/relay/') || path.startsWith('/agent/')) { res.writeHead(404); return res.end(); }
	if (!agent) return statusPage(req, res, 503, 'Your Mac is offline', 'The Mac has not connected to this relay. It reconnects automatically when it is awake and online.');
	const a = agent;
	if (a.pending.size >= MAX_PENDING) return statusPage(req, res, 503, 'Relay busy', 'Too many requests in flight. Try again in a moment.');

	const headers = {};
	for (const [k, v] of Object.entries(req.headers)) if (!STRIP_REQ.has(k) && !k.startsWith('x-forwarded-')) headers[k] = v;
	headers['x-forwarded-for'] = clientIp(req);
	headers['x-forwarded-proto'] = clientProto(req);
	headers['x-forwarded-host'] = req.headers.host || '';
	headers['x-relayed'] = '1';

	const id = ++a.seq;
	const e = { id, req, res, upInflight: 0, upBytes: 0, downBytes: 0, headersSent: false, done: false, timer: null };
	a.pending.set(id, e);
	const send = (h, body) => { if (a.conn.readyState === 1) a.conn.send(ws.pack(h, body)); };
	const finish = () => { if (e.done) return; e.done = true; clearTimeout(e.timer); a.pending.delete(id); };
	const fail = (status, title, detail) => { if (e.done) return; send({ id, t: 'abort' }); finish(); statusPage(req, res, status, title, detail); };
	const touch = () => { clearTimeout(e.timer); e.timer = setTimeout(() => fail(504, 'The Mac did not answer', 'The relay is connected but the Mac stopped responding.'), e.headersSent ? IDLE_TIMEOUT_MS : HEAD_TIMEOUT_MS); };
	e.fail = fail; e.finish = finish; e.touch = touch; e.send = send;
	touch();

	send({ id, t: 'req', method: req.method, url: req.url, headers });
	req.on('data', (chunk) => {
		e.upBytes += chunk.length;
		if (e.upBytes > MAX_BODY) return fail(413, 'Upload too large', `Bodies over ${MAX_BODY / 1048576} MB cannot go through the relay.`);
		e.upInflight++;
		send({ id, t: 'data' }, chunk);
		if (e.upInflight >= WINDOW) req.pause();
	});
	req.on('end', () => send({ id, t: 'end' }));
	req.on('error', () => fail(400, 'Bad request', 'Upload interrupted.'));
	res.on('close', () => { if (!e.done) { send({ id, t: 'abort' }); finish(); } });
});

function onAgentMessage(a, data) {
	let msg;
	try { msg = ws.unpack(data); } catch { return; }
	const h = msg.header;
	const e = a.pending.get(h.id);
	if (!e || e.done) return;
	switch (h.t) {
		case 'res': {
			if (e.headersSent) return;
			e.headersSent = true; e.touch();
			const out = {};
			for (const [k, v] of Object.entries(h.headers || {})) if (!STRIP_RES.has(k.toLowerCase())) out[k] = v;
			try { e.res.writeHead(h.status || 502, out); } catch (err) { return e.fail(502, 'Relay error', err.message); }
			break;
		}
		case 'data': {
			if (!e.headersSent) return e.fail(502, 'Relay error', 'Body before headers');
			e.downBytes += msg.body.length; e.touch();
			if (e.downBytes > MAX_BODY) return e.fail(502, 'Response too large', `Responses over ${MAX_BODY / 1048576} MB cannot go through the relay.`);
			e.res.write(msg.body, () => e.send({ id: h.id, t: 'ack' })); // ack once the chunk left our buffer → flow control
			break;
		}
		case 'end': { e.finish(); if (e.headersSent) e.res.end(); else e.res.writeHead(502).end(); served++; break; }
		case 'ack': { e.upInflight = Math.max(0, e.upInflight - 1); if (e.upInflight < WINDOW && e.req.isPaused()) e.req.resume(); break; }
		case 'err': { e.fail(502, 'The Mac could not handle the request', String(h.message || 'unknown error')); break; }
	}
}

// ---------------------------------------------------------------- Mac → relay
server.on('upgrade', (req, socket, head) => {
	const path = req.url.split('?')[0];
	if (path !== '/agent/connect') return ws.reject(socket, 404, 'Not Found');
	const auth = String(req.headers.authorization || '');
	if (!auth.startsWith('Bearer ') || !safeEqual(auth.slice(7).trim(), SECRET)) {
		log(`agent auth failed from ${clientIp(req)}`);
		return ws.reject(socket, 401, 'Unauthorized');
	}
	const conn = ws.accept(req, socket, head, { maxMessage: MAX_MESSAGE });
	if (!conn) return;
	if (agent) { log('replacing previous agent connection'); const old = agent; agent = null; failPending(old, 'Replaced by a new connection from the Mac'); old.conn.close(4000, 'replaced'); }
	const a = { conn, name: String(req.headers['x-agent-name'] || 'mac').slice(0, 60), since: Date.now(), pending: new Map(), seq: 0, lastPong: Date.now() };
	agent = a;
	log(`agent "${a.name}" connected from ${clientIp(req)}`);

	conn.on('message', (data, isBinary) => { if (isBinary) onAgentMessage(a, data); });
	conn.on('pong', () => { a.lastPong = Date.now(); });
	conn.on('ping', () => { a.lastPong = Date.now(); });
	conn.on('error', (e) => log('agent socket error:', e.message));
	conn.on('close', (code, reason) => {
		clearInterval(hb);
		if (agent === a) agent = null;
		log(`agent "${a.name}" disconnected (${code} ${reason || ''})`);
		failPending(a, 'The Mac disconnected while answering.');
	});
	const hb = setInterval(() => {
		if (conn.readyState !== 1) return clearInterval(hb);
		if (Date.now() - a.lastPong > PING_EVERY_MS + PONG_GRACE_MS) { log('agent heartbeat timeout'); conn.terminate(); return clearInterval(hb); }
		conn.ping();
	}, PING_EVERY_MS);
});

function failPending(a, why) {
	for (const e of [...a.pending.values()]) e.fail(502, 'Your Mac is offline', why);
}

server.keepAliveTimeout = 65 * 1000;
server.headersTimeout = 70 * 1000;
server.listen(PORT, '0.0.0.0', () => {
	log(`Mac Remote relay listening on :${PORT} (TRUST_PROXY=${TRUST_PROXY})`);
	log('The Mac connects to exactly one relay process: run a single instance (fly deploy --ha=false; one Render instance).');
});
process.on('SIGTERM', () => { server.close(() => process.exit(0)); setTimeout(() => process.exit(0), 2000); });
