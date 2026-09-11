#!/usr/bin/env node
// Generates the PWA icons (violet rounded square with a power glyph) as PNGs
// using nothing but zlib. Run: node tools/make-icons.js
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const zlib = require('node:zlib');

function crc32(buf) {
	let c, crc = 0xffffffff;
	for (let n = 0; n < buf.length; n++) {
		c = (crc ^ buf[n]) & 0xff;
		for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
		crc = (crc >>> 8) ^ c;
	}
	return (crc ^ 0xffffffff) >>> 0;
}
function chunk(type, data) {
	const len = Buffer.alloc(4); len.writeUInt32BE(data.length);
	const td = Buffer.concat([Buffer.from(type, 'ascii'), data]);
	const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(td));
	return Buffer.concat([len, td, crc]);
}
function png(size, pixel) {
	const raw = Buffer.alloc((size * 4 + 1) * size);
	for (let y = 0; y < size; y++) {
		raw[y * (size * 4 + 1)] = 0;
		for (let x = 0; x < size; x++) {
			const [r, g, b, a] = pixel(x + 0.5, y + 0.5);
			const o = y * (size * 4 + 1) + 1 + x * 4;
			raw[o] = r; raw[o + 1] = g; raw[o + 2] = b; raw[o + 3] = a;
		}
	}
	const ihdr = Buffer.alloc(13);
	ihdr.writeUInt32BE(size, 0); ihdr.writeUInt32BE(size, 4);
	ihdr[8] = 8; ihdr[9] = 6; ihdr[10] = 0; ihdr[11] = 0; ihdr[12] = 0;
	return Buffer.concat([
		Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
		chunk('IHDR', ihdr), chunk('IDAT', zlib.deflateSync(raw, { level: 9 })), chunk('IEND', Buffer.alloc(0)),
	]);
}

const clamp01 = (v) => Math.max(0, Math.min(1, v));
const mix = (a, b, t) => a + (b - a) * t;
// Signed distance to a rounded rectangle centred at (cx, cy).
function sdRoundRect(x, y, cx, cy, half, r) {
	const qx = Math.abs(x - cx) - half + r, qy = Math.abs(y - cy) - half + r;
	return Math.min(Math.max(qx, qy), 0) + Math.hypot(Math.max(qx, 0), Math.max(qy, 0)) - r;
}

function icon(size, { rounded }) {
	const c = size / 2;
	const R = size * 0.225;              // corner radius (iOS-ish)
	const ringR = size * 0.235, ringW = size * 0.075;
	const gapHalf = Math.PI * 0.16;      // half-angle of the gap at the top
	const barW = size * 0.075, barTop = c - ringR - size * 0.02, barBottom = c - size * 0.02;
	return png(size, (x, y) => {
		// background: diagonal violet gradient
		const t = clamp01((x + y) / (2 * size));
		const bg = [Math.round(mix(0xa5, 0x5a, t)), Math.round(mix(0x8b, 0x3f, t)), Math.round(mix(0xff, 0xd6, t))];
		let alpha = 1;
		if (rounded) alpha = clamp01(0.5 - sdRoundRect(x, y, c, c, size / 2, R));
		// glyph coverage
		const dx = x - c, dy = y - c, d = Math.hypot(dx, dy);
		let ring = clamp01(0.5 - (Math.abs(d - ringR) - ringW / 2));
		const ang = Math.atan2(dx, -dy); // 0 at top
		if (Math.abs(ang) < gapHalf) ring = 0;
		// soften gap ends with round caps
		for (const s of [-1, 1]) {
			const ex = c + Math.sin(s * gapHalf) * ringR, ey = c - Math.cos(s * gapHalf) * ringR;
			ring = Math.max(ring, clamp01(0.5 - (Math.hypot(x - ex, y - ey) - ringW / 2)));
		}
		const barCov = clamp01(0.5 - Math.max(Math.abs(dx) - barW / 2, Math.max(barTop - y, y - barBottom)));
		const capCov = Math.max(clamp01(0.5 - (Math.hypot(x - c, y - barTop) - barW / 2)), clamp01(0.5 - (Math.hypot(x - c, y - barBottom) - barW / 2)));
		const glyph = Math.max(ring, barCov, capCov);
		const col = bg.map((v) => Math.round(mix(v, 255, glyph)));
		return [col[0], col[1], col[2], Math.round(alpha * 255)];
	});
}

const out = path.join(__dirname, '..', 'public');
fs.writeFileSync(path.join(out, 'icon-180.png'), icon(180, { rounded: false })); // iOS masks its own corners
fs.writeFileSync(path.join(out, 'icon-192.png'), icon(192, { rounded: true }));
fs.writeFileSync(path.join(out, 'icon-512.png'), icon(512, { rounded: false }));  // maskable: full bleed
console.log('icons written to', out);
