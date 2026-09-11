'use strict';
// Minimal RFC 6455 WebSocket implementation (server accept + client connect). No dependencies.
// Supports text/binary frames, fragmentation, ping/pong, close handshake, masking rules.
// Receive path never concatenates partial frames, so a large frame arriving in small TCP chunks costs O(n), not O(n^2).

const crypto = require('node:crypto');
const http = require('node:http');
const https = require('node:https');
const { EventEmitter } = require('node:events');

const GUID = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';
const OP = { CONT: 0, TEXT: 1, BINARY: 2, CLOSE: 8, PING: 9, PONG: 10 };

class WebSocketConn extends EventEmitter {
	constructor(socket, { isServer, maxMessage = 64 * 1024 * 1024 } = {}) {
		super();
		this.socket = socket;
		this.isServer = Boolean(isServer);
		this.maxMessage = maxMessage;
		this.readyState = 1; // 1 open, 2 closing, 3 closed
		this._chunks = []; // received TCP chunks not yet consumed (never concatenated until a whole frame is present)
		this._len = 0;
		this._frag = null; // { opcode, chunks, size }
		this._closeSent = false;
		this._closeTimer = null;
		this.on('error', () => {}); // a socket error must never crash the process; consumers may add their own listener
		socket.setNoDelay(true);
		socket.on('data', (d) => this._onData(d));
		socket.on('error', (e) => this.emit('error', e));
		socket.on('close', () => this._finish(1006, ''));
		socket.on('end', () => socket.end());
	}

	_onData(chunk) {
		if (this.readyState === 3) return;
		this._chunks.push(chunk);
		this._len += chunk.length;
		try {
			while (this._parseFrame()) { /* keep going */ }
		} catch (e) {
			this._fail(e.wsCode || 1002, e.message);
		}
	}

	// First n bytes of the receive queue without consuming them (copies at most 14 bytes).
	_peek(n) {
		const first = this._chunks[0];
		if (!first) return Buffer.alloc(0);
		if (first.length >= n) return first.subarray(0, n);
		const out = Buffer.alloc(Math.min(n, this._len));
		let off = 0;
		for (const c of this._chunks) { const take = Math.min(c.length, out.length - off); c.copy(out, off, 0, take); off += take; if (off >= out.length) break; }
		return out;
	}
	_take(total) {
		const buf = this._chunks.length === 1 ? this._chunks[0] : Buffer.concat(this._chunks, this._len);
		const rest = buf.subarray(total);
		this._chunks = rest.length ? [rest] : [];
		this._len = rest.length;
		return buf.subarray(0, total);
	}

	_parseFrame() {
		if (this._len < 2) return false;
		const h = this._peek(14);
		const fin = (h[0] & 0x80) !== 0;
		const rsv = h[0] & 0x70;
		const opcode = h[0] & 0x0f;
		const masked = (h[1] & 0x80) !== 0;
		let len = h[1] & 0x7f;
		let off = 2;
		if (rsv) throw wsError('RSV bits set', 1002);
		if (this.isServer && !masked) throw wsError('Client frames must be masked', 1002);
		if (!this.isServer && masked) throw wsError('Server frames must not be masked', 1002);
		if (len === 126) {
			if (h.length < off + 2) return false;
			len = h.readUInt16BE(off); off += 2;
		} else if (len === 127) {
			if (h.length < off + 8) return false;
			const big = h.readBigUInt64BE(off); off += 8;
			if (big > BigInt(this.maxMessage)) throw wsError('Frame too large', 1009);
			len = Number(big);
		}
		if (len > this.maxMessage) throw wsError('Frame too large', 1009);
		if (opcode >= 8 && (!fin || len > 125)) throw wsError('Bad control frame', 1002);
		if (masked) off += 4;
		if (this._len < off + len) return false; // wait for the rest without copying anything
		const b = this._take(off + len);
		const mask = masked ? b.subarray(off - 4, off) : null;
		const payload = Buffer.from(b.subarray(off, off + len)); // own copy: the source buffer may be reused
		if (mask) for (let i = 0; i < payload.length; i++) payload[i] ^= mask[i & 3];

		if (opcode >= 8) {
			// control frame
			if (opcode === OP.CLOSE) {
				let code = 1005, reason = '';
				if (payload.length >= 2) { code = payload.readUInt16BE(0); reason = payload.subarray(2).toString('utf8'); }
				else if (payload.length === 1) throw wsError('Bad close payload', 1002);
				if (!this._closeSent) { this._sendFrame(OP.CLOSE, payload.length >= 2 ? payload.subarray(0, 2) : Buffer.alloc(0)); this._closeSent = true; }
				this.readyState = 2;
				this._finish(code, reason);
				return false;
			}
			if (opcode === OP.PING) { this.emit('ping', payload); if (this.readyState === 1) this._sendFrame(OP.PONG, payload); return true; }
			if (opcode === OP.PONG) { this.emit('pong', payload); return true; }
			throw wsError('Unknown control opcode', 1002);
		}

		if (opcode === OP.CONT) {
			if (!this._frag) throw wsError('Unexpected continuation', 1002);
			this._frag.size += payload.length;
			if (this._frag.size > this.maxMessage) throw wsError('Message too large', 1009);
			this._frag.chunks.push(payload);
			if (fin) { const f = this._frag; this._frag = null; this._deliver(f.opcode, Buffer.concat(f.chunks)); }
			return true;
		}
		if (opcode !== OP.TEXT && opcode !== OP.BINARY) throw wsError('Unknown opcode', 1002);
		if (this._frag) throw wsError('New data frame during fragmented message', 1002);
		if (fin) this._deliver(opcode, payload);
		else this._frag = { opcode, chunks: [payload], size: payload.length };
		return true;
	}

	_deliver(opcode, payload) {
		if (opcode === OP.TEXT) {
			const text = payload.toString('utf8');
			if (Buffer.byteLength(text, 'utf8') !== payload.length) throw wsError('Invalid UTF-8', 1007);
			this.emit('message', text, false);
		} else this.emit('message', payload, true);
	}

	_sendFrame(opcode, payload) {
		if (this.socket.destroyed) return false;
		const len = payload.length;
		let header;
		if (len < 126) { header = Buffer.alloc(2); header[1] = len; }
		else if (len < 65536) { header = Buffer.alloc(4); header[1] = 126; header.writeUInt16BE(len, 2); }
		else { header = Buffer.alloc(10); header[1] = 127; header.writeBigUInt64BE(BigInt(len), 2); }
		header[0] = 0x80 | opcode;
		if (this.isServer) return this.socket.write(Buffer.concat([header, payload]));
		// clients must mask
		header[1] |= 0x80;
		const mask = crypto.randomBytes(4);
		const masked = Buffer.allocUnsafe(len);
		for (let i = 0; i < len; i++) masked[i] = payload[i] ^ mask[i & 3];
		return this.socket.write(Buffer.concat([header, mask, masked]));
	}

	send(data) {
		if (this.readyState !== 1) return false;
		if (typeof data === 'string') return this._sendFrame(OP.TEXT, Buffer.from(data, 'utf8'));
		return this._sendFrame(OP.BINARY, Buffer.isBuffer(data) ? data : Buffer.from(data));
	}
	ping(data = Buffer.alloc(0)) { if (this.readyState === 1) this._sendFrame(OP.PING, Buffer.from(data)); }

	close(code = 1000, reason = '') {
		if (this.readyState >= 2) return;
		this.readyState = 2;
		const r = Buffer.from(String(reason), 'utf8').subarray(0, 123);
		const payload = Buffer.alloc(2 + r.length);
		payload.writeUInt16BE(code, 0); r.copy(payload, 2);
		this._sendFrame(OP.CLOSE, payload);
		this._closeSent = true;
		this._closeTimer = setTimeout(() => this._finish(code, reason), 1500);
	}
	terminate() { this._finish(1006, 'terminated'); }

	_fail(code, reason) {
		if (this.readyState === 1) { try { this.close(code, reason); } catch {} }
		clearTimeout(this._closeTimer);
		this._closeTimer = setTimeout(() => this._finish(code, reason), 300);
	}
	_finish(code, reason) {
		if (this.readyState === 3) return;
		this.readyState = 3;
		clearTimeout(this._closeTimer);
		this.socket.destroy();
		this.emit('close', code, reason);
	}
}

function wsError(msg, code) { const e = new Error(msg); e.wsCode = code; return e; }

function acceptKey(key) { return crypto.createHash('sha1').update(key + GUID).digest('base64'); }

// Server side: call from http.Server 'upgrade'. Returns a WebSocketConn or null (after rejecting).
function accept(req, socket, head, opts = {}) {
	const key = req.headers['sec-websocket-key'];
	if (String(req.headers.upgrade || '').toLowerCase() !== 'websocket' || !key || req.headers['sec-websocket-version'] !== '13') {
		socket.write('HTTP/1.1 400 Bad Request\r\nConnection: close\r\n\r\n');
		socket.destroy();
		return null;
	}
	socket.write('HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: ' + acceptKey(key) + '\r\n\r\n');
	const conn = new WebSocketConn(socket, { isServer: true, maxMessage: opts.maxMessage });
	if (head && head.length) setImmediate(() => conn._onData(head)); // after the caller has attached listeners
	return conn;
}

function reject(socket, status = 401, text = 'Unauthorized') {
	socket.write(`HTTP/1.1 ${status} ${text}\r\nConnection: close\r\nContent-Length: 0\r\n\r\n`);
	socket.destroy();
}

// Client side: connect(url, { headers, timeout, maxMessage }) -> Promise<WebSocketConn>
function connect(url, opts = {}) {
	return new Promise((resolve, reject) => {
		const u = new URL(url);
		const secure = u.protocol === 'wss:' || u.protocol === 'https:';
		if (!secure && u.protocol !== 'ws:' && u.protocol !== 'http:') return reject(new Error(`Unsupported protocol ${u.protocol}`));
		const key = crypto.randomBytes(16).toString('base64');
		const req = (secure ? https : http).request({
			host: u.hostname, port: u.port || (secure ? 443 : 80), path: u.pathname + u.search, method: 'GET',
			headers: { ...(opts.headers || {}), Connection: 'Upgrade', Upgrade: 'websocket', 'Sec-WebSocket-Version': '13', 'Sec-WebSocket-Key': key, Host: u.host },
			timeout: opts.timeout || 15000,
		});
		req.on('upgrade', (res, socket, head) => {
			if (res.headers['sec-websocket-accept'] !== acceptKey(key)) { socket.destroy(); return reject(new Error('Bad Sec-WebSocket-Accept')); }
			const conn = new WebSocketConn(socket, { isServer: false, maxMessage: opts.maxMessage });
			if (head && head.length) setImmediate(() => conn._onData(head)); // after the caller has attached listeners
			resolve(conn);
		});
		req.on('response', (res) => { const e = new Error(`WebSocket handshake failed: HTTP ${res.statusCode}`); e.status = res.statusCode; res.resume(); reject(e); });
		req.on('timeout', () => { req.destroy(new Error('WebSocket connect timeout')); });
		req.on('error', reject);
		req.end();
	});
}

// Relay message framing: [uint32 BE header length][JSON header][raw body]
function pack(header, body = Buffer.alloc(0)) {
	const h = Buffer.from(JSON.stringify(header), 'utf8');
	const len = Buffer.alloc(4); len.writeUInt32BE(h.length, 0);
	return Buffer.concat([len, h, body]);
}
function unpack(buf) {
	if (!Buffer.isBuffer(buf) || buf.length < 4) throw new Error('Bad relay message');
	const hl = buf.readUInt32BE(0);
	if (buf.length < 4 + hl) throw new Error('Truncated relay message');
	return { header: JSON.parse(buf.subarray(4, 4 + hl).toString('utf8')), body: buf.subarray(4 + hl) };
}

module.exports = { WebSocketConn, accept, reject, connect, pack, unpack, OP };
