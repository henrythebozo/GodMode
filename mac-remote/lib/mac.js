'use strict';
// macOS control primitives. Everything shells out to tools that ship with
// macOS (osascript, screencapture, sips, pbcopy, pmset, open, say) plus the
// optional Homebrew tool `cliclick` for mouse/keyboard events.
//
// Every function returns a Promise and throws an Error with a readable
// message when the underlying command fails, so the HTTP layer can pass the
// text straight to the phone.

const { execFile, spawn } = require('node:child_process');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');

const IS_MAC = process.platform === 'darwin';

// ---------------------------------------------------------------- helpers
function run(cmd, args = [], opts = {}) {
	return new Promise((resolve, reject) => {
		execFile(cmd, args, { timeout: opts.timeout ?? 15000, maxBuffer: 8 * 1024 * 1024, encoding: opts.encoding ?? 'utf8', ...opts }, (err, stdout, stderr) => {
			if (err) {
				const msg = (stderr || err.message || '').toString().trim();
				const e = new Error(msg || `${cmd} failed`);
				e.code = err.code;
				e.stdout = stdout;
				return reject(e);
			}
			resolve(stdout);
		});
	});
}

function osa(script, argv = []) {
	// Pass user text through argv so we never have to escape it inside AppleScript.
	const args = [];
	for (const line of script.split('\n')) args.push('-e', line);
	if (argv.length) args.push('--', ...argv);
	return run('osascript', args).then((s) => s.replace(/\n$/, ''));
}

function jxa(script, argv = []) {
	const args = ['-l', 'JavaScript', '-e', script];
	if (argv.length) args.push('--', ...argv);
	return run('osascript', args).then((s) => s.replace(/\n$/, ''));
}

let cliclickPath = null;
async function findCliclick() {
	if (cliclickPath !== null) return cliclickPath;
	for (const p of ['/opt/homebrew/bin/cliclick', '/usr/local/bin/cliclick']) {
		try { await fs.access(p); cliclickPath = p; return p; } catch {}
	}
	try {
		cliclickPath = (await run('which', ['cliclick'])).trim() || false;
	} catch { cliclickPath = false; }
	return cliclickPath;
}

// ---------------------------------------------------------------- screen
let screenCache = { at: 0, w: 0, h: 0 };
async function screenSize() {
	if (Date.now() - screenCache.at < 60000 && screenCache.w) return { w: screenCache.w, h: screenCache.h };
	// Logical (points, not pixels) size of the main display. Mouse coordinates use this space.
	let w, h;
	try {
		const out = await osa('tell application "Finder" to get bounds of window of desktop');
		const parts = out.split(',').map((n) => parseInt(n.trim(), 10));
		if (parts.length !== 4 || parts.some(Number.isNaN)) throw new Error(out);
		w = parts[2] - parts[0]; h = parts[3] - parts[1];
	} catch {
		const out = await jxa("ObjC.import('AppKit'); var f = $.NSScreen.mainScreen.frame; f.size.width + ',' + f.size.height");
		[w, h] = out.split(',').map(Number);
		if (!w || !h) throw new Error(`Could not read screen size: ${out}`);
	}
	screenCache = { at: Date.now(), w, h };
	return { w: screenCache.w, h: screenCache.h };
}

async function screenshot({ maxWidth = 1280, quality = 60 } = {}) {
	const file = path.join(os.tmpdir(), `mr-shot-${process.pid}-${Date.now()}.jpg`);
	try {
		// -x no sound, -C show cursor, -t jpg
		await run('screencapture', ['-x', '-C', '-t', 'jpg', file], { timeout: 8000 });
		// Downscale so a phone on LTE is not pulling 5 MB Retina captures.
		await run('sips', ['-Z', String(maxWidth), '-s', 'format', 'jpeg', '-s', 'formatOptions', String(quality), file, '--out', file], { timeout: 8000 });
		return await fs.readFile(file);
	} catch (e) {
		if (/could not create image|not permitted|Permission/i.test(e.message) || e.message === '') {
			throw new Error('screencapture failed. Give this process Screen Recording permission in System Settings → Privacy & Security → Screen Recording, then restart the server.');
		}
		throw e;
	} finally {
		fs.unlink(file).catch(() => {});
	}
}

// ---------------------------------------------------------------- mouse
// x/y are logical screen coordinates (points).
function pt(n) { return String(Math.round(n)); }

async function cgMouse(events, x, y, button = 'left') {
	// Fallback when cliclick is missing: synthesize events with CoreGraphics via the JXA ObjC bridge.
	const btn = button === 'right' ? '$.kCGMouseButtonRight' : '$.kCGMouseButtonLeft';
	const script = `
ObjC.import('CoreGraphics');
function post(type){ var e = $.CGEventCreateMouseEvent(null, type, {x:${x}, y:${y}}, ${btn}); $.CGEventPost($.kCGHIDEventTap, e); }
${events.map((ev) => `post(${ev});`).join(' delay(0.02); ')}
'ok'`;
	return jxa(script);
}

async function mouseMove(x, y) {
	const cc = await findCliclick();
	if (cc) return run(cc, [`m:${pt(x)},${pt(y)}`]);
	return cgMouse(['$.kCGEventMouseMoved'], x, y);
}

async function mouseClick(x, y, { button = 'left', double = false } = {}) {
	const cc = await findCliclick();
	if (cc) {
		const op = button === 'right' ? 'rc' : double ? 'dc' : 'c';
		return run(cc, [`${op}:${pt(x)},${pt(y)}`]);
	}
	if (button === 'right') return cgMouse(['$.kCGEventMouseMoved', '$.kCGEventRightMouseDown', '$.kCGEventRightMouseUp'], x, y, 'right');
	const seq = ['$.kCGEventMouseMoved', '$.kCGEventLeftMouseDown', '$.kCGEventLeftMouseUp'];
	if (double) seq.push('$.kCGEventLeftMouseDown', '$.kCGEventLeftMouseUp');
	return cgMouse(seq, x, y);
}

async function mouseDrag(x1, y1, x2, y2) {
	const cc = await findCliclick();
	if (cc) return run(cc, [`dd:${pt(x1)},${pt(y1)}`, 'w:150', `dm:${pt(x2)},${pt(y2)}`, 'w:150', `du:${pt(x2)},${pt(y2)}`]);
	const script = `
ObjC.import('CoreGraphics');
function post(type,x,y){ var e = $.CGEventCreateMouseEvent(null, type, {x:x, y:y}, $.kCGMouseButtonLeft); $.CGEventPost($.kCGHIDEventTap, e); }
post($.kCGEventMouseMoved, ${x1}, ${y1}); delay(0.05);
post($.kCGEventLeftMouseDown, ${x1}, ${y1}); delay(0.15);
post($.kCGEventLeftMouseDragged, ${(x1 + x2) / 2}, ${(y1 + y2) / 2}); delay(0.05);
post($.kCGEventLeftMouseDragged, ${x2}, ${y2}); delay(0.15);
post($.kCGEventLeftMouseUp, ${x2}, ${y2});
'ok'`;
	return jxa(script);
}

async function mouseScroll(dx, dy) {
	// Positive dy scrolls content up (like rolling the wheel away from you).
	const lines = (n) => Math.max(-30, Math.min(30, Math.round(n)));
	const script = `
ObjC.import('CoreGraphics');
var e = $.CGEventCreateScrollWheelEvent2(null, $.kCGScrollEventUnitLine, 2, ${lines(dy)}, ${lines(dx)}, 0);
$.CGEventPost($.kCGHIDEventTap, e);
'ok'`;
	return jxa(script);
}

// ---------------------------------------------------------------- keyboard
const KEY_CODES = {
	return: 36, enter: 36, tab: 48, space: 49, delete: 51, backspace: 51, escape: 53, esc: 53,
	forwarddelete: 117, home: 115, end: 119, pageup: 116, pagedown: 121,
	left: 123, right: 124, down: 125, up: 126,
	f1: 122, f2: 120, f3: 99, f4: 118, f5: 96, f6: 97, f7: 98, f8: 100, f9: 101, f10: 109, f11: 103, f12: 111,
	capslock: 57, fn: 63,
};
const MODS = { cmd: 'command down', command: 'command down', shift: 'shift down', ctrl: 'control down', control: 'control down', alt: 'option down', opt: 'option down', option: 'option down' };

async function typeText(text) {
	if (!text) return;
	// System Events keystroke handles most unicode. Newlines become Return presses.
	const chunks = String(text).split(/\r?\n/);
	const lines = ['on run argv', 'tell application "System Events"'];
	const argv = [];
	chunks.forEach((chunk, i) => {
		if (chunk.length) { argv.push(chunk); lines.push(`keystroke (item ${argv.length} of argv)`); }
		if (i < chunks.length - 1) lines.push('key code 36');
	});
	lines.push('end tell', 'end run');
	return osa(lines.join('\n'), argv);
}

async function pressKey(key, mods = []) {
	const k = String(key || '').toLowerCase();
	const using = mods.map((m) => MODS[String(m).toLowerCase()]).filter(Boolean);
	const usingClause = using.length ? ` using {${using.join(', ')}}` : '';
	if (KEY_CODES[k] !== undefined) return osa(`tell application "System Events" to key code ${KEY_CODES[k]}${usingClause}`);
	if (k.length === 1) return osa(`on run argv\ntell application "System Events" to keystroke (item 1 of argv)${usingClause}\nend run`, [k]);
	throw new Error(`Unknown key: ${key}`);
}

// ---------------------------------------------------------------- audio / media
async function getVolume() {
	const out = await osa('get volume settings');
	// "output volume:50, input volume:75, alert volume:100, output muted:false"
	const m = /output volume:(\d+).*output muted:(true|false)/.exec(out);
	return { level: m ? parseInt(m[1], 10) : null, muted: m ? m[2] === 'true' : null };
}
async function setVolume(level) {
	const n = Math.max(0, Math.min(100, Math.round(level)));
	await osa(`set volume output volume ${n}`);
	return getVolume();
}
async function setMuted(muted) {
	await osa(muted ? 'set volume with output muted' : 'set volume without output muted');
	return getVolume();
}

async function runningApps() {
	const out = await osa('tell application "System Events" to get name of every process whose background only is false');
	return out.split(', ').map((s) => s.trim()).filter(Boolean);
}

async function mediaControl(action) {
	const verb = { playpause: 'playpause', play: 'play', pause: 'pause', next: 'next track', prev: 'previous track', previous: 'previous track' }[action];
	if (!verb) throw new Error(`Unknown media action: ${action}`);
	const apps = await runningApps();
	const player = ['Spotify', 'Music', 'TV', 'Podcasts'].find((a) => apps.includes(a));
	if (player) return osa(`tell application "${player}" to ${verb}`);
	// Nothing scriptable is open: fall back to the F8/F7/F9 media keys (works for browser tabs when "Use F1, F2… as standard keys" is off).
	const code = { playpause: 100, play: 100, pause: 100, next: 101, prev: 98, previous: 98 }[action];
	return osa(`tell application "System Events" to key code ${code}`);
}

async function nowPlaying() {
	const apps = await runningApps();
	for (const app of ['Spotify', 'Music']) {
		if (!apps.includes(app)) continue;
		try {
			const state = await osa(`tell application "${app}" to get player state as string`);
			if (state !== 'playing' && state !== 'paused') continue;
			const info = await osa(`tell application "${app}" to get (name of current track) & "\n" & (artist of current track)`);
			const [title, artist] = info.split('\n');
			return { app, state, title, artist };
		} catch {}
	}
	return null;
}

// ---------------------------------------------------------------- apps / system
async function frontmostApp() {
	try { return await osa('tell application "System Events" to get name of first process whose frontmost is true'); } catch { return null; }
}
async function openApp(name) { return run('open', ['-a', name]); }
async function focusApp(name) { return osa('on run argv\ntell application (item 1 of argv) to activate\nend run', [name]); }
async function quitApp(name) { return osa('on run argv\ntell application (item 1 of argv) to quit\nend run', [name]); }
async function openUrl(url) {
	if (!/^https?:\/\//i.test(url)) throw new Error('URL must start with http:// or https://');
	return run('open', [url]);
}

async function power(action) {
	switch (action) {
		case 'lock': return osa('tell application "System Events" to keystroke "q" using {command down, control down}');
		case 'sleep': return run('pmset', ['sleepnow']);
		case 'displaysleep': return run('pmset', ['displaysleepnow']);
		case 'wake': return run('caffeinate', ['-u', '-t', '3']);
		case 'restart': return osa('tell application "System Events" to restart');
		case 'shutdown': return osa('tell application "System Events" to shut down');
		default: throw new Error(`Unknown power action: ${action}`);
	}
}

async function clipboardGet() { return run('pbpaste'); }
function clipboardSet(text) {
	return new Promise((resolve, reject) => {
		const p = spawn('pbcopy');
		p.on('error', reject);
		p.on('close', (code) => (code === 0 ? resolve() : reject(new Error(`pbcopy exited ${code}`))));
		p.stdin.end(String(text ?? ''));
	});
}

async function say(text, voice) {
	const args = [];
	if (voice) args.push('-v', voice);
	args.push('--', String(text));
	return run('say', args, { timeout: 60000 });
}
async function notify(title, body) {
	return osa('on run argv\ndisplay notification (item 2 of argv) with title (item 1 of argv)\nend run', [String(title || 'Mac Remote'), String(body || '')]);
}

async function diskUsage() {
	try {
		const out = await run('df', ['-k', '/']);
		const line = out.trim().split('\n').pop().split(/\s+/);
		const total = parseInt(line[1], 10) * 1024, used = parseInt(line[2], 10) * 1024;
		return { total, used, free: total - used };
	} catch { return null; }
}

async function cpuPercent() {
	if (!IS_MAC) return null;
	try {
		const out = await run('top', ['-l', '1', '-n', '0', '-s', '0'], { timeout: 6000 });
		const m = /CPU usage:\s*([\d.]+)% user,\s*([\d.]+)% sys/.exec(out);
		return m ? Math.round(parseFloat(m[1]) + parseFloat(m[2])) : null;
	} catch { return null; }
}

async function systemStatus() {
	const [front, vol, disk, cpu, screen, cc, playing] = await Promise.all([
		frontmostApp().catch(() => null),
		getVolume().catch(() => null),
		diskUsage(),
		cpuPercent(),
		screenSize().catch(() => null),
		findCliclick(),
		nowPlaying().catch(() => null),
	]);
	return {
		hostname: os.hostname(),
		platform: process.platform,
		uptime: os.uptime(),
		load: os.loadavg(),
		cpu,
		mem: { total: os.totalmem(), free: os.freemem() },
		disk,
		frontApp: front,
		volume: vol,
		screen,
		nowPlaying: playing,
		capabilities: { cliclick: Boolean(cc), mac: IS_MAC },
		time: Date.now(),
	};
}

function shell(cmd, { cwd, timeout = 30000 } = {}) {
	return new Promise((resolve) => {
		const started = Date.now();
		const sh = IS_MAC ? '/bin/zsh' : '/bin/bash';
		execFile(sh, ['-lc', cmd], { cwd: cwd || os.homedir(), timeout, maxBuffer: 4 * 1024 * 1024, env: { ...process.env, TERM: 'dumb' } }, (err, stdout, stderr) => {
			resolve({
				stdout: stdout ?? '',
				stderr: stderr ?? '',
				code: err ? (err.code ?? 1) : 0,
				killed: Boolean(err && err.killed),
				ms: Date.now() - started,
			});
		});
	});
}

module.exports = {
	IS_MAC,
	screenSize, screenshot,
	mouseMove, mouseClick, mouseDrag, mouseScroll,
	typeText, pressKey, KEY_CODES,
	getVolume, setVolume, setMuted, mediaControl, nowPlaying,
	runningApps, frontmostApp, openApp, focusApp, quitApp, openUrl,
	power, clipboardGet, clipboardSet, say, notify,
	systemStatus, shell, findCliclick,
};
