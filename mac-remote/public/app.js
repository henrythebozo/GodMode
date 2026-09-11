/* Mac Remote — phone UI. Plain JS, no build step. */
(() => {
	'use strict';
	const $ = (s, r = document) => r.querySelector(s);
	const $$ = (s, r = document) => [...r.querySelectorAll(s)];

	// ---------------------------------------------------------------- api
	class ApiError extends Error { constructor(status, msg) { super(msg); this.status = status; } }
	async function api(method, path, body, raw) {
		const opts = { method, credentials: 'same-origin', headers: {} };
		if (body !== undefined && !(body instanceof Blob)) { opts.headers['Content-Type'] = 'application/json'; opts.body = JSON.stringify(body); }
		else if (body instanceof Blob) { opts.headers['Content-Type'] = 'application/octet-stream'; opts.body = body; }
		const res = await fetch(path, opts);
		if (res.status === 401 && path !== '/api/login') { showLogin(); throw new ApiError(401, 'Logged out'); }
		if (raw) { if (!res.ok) throw new ApiError(res.status, (await res.json().catch(() => ({}))).error || res.statusText); return res; }
		const data = await res.json().catch(() => ({}));
		if (!res.ok) throw new ApiError(res.status, data.error || res.statusText);
		return data;
	}
	const post = (path, body) => api('POST', path, body);

	let toastTimer;
	function toast(msg, kind = '') {
		const t = $('#toast');
		t.textContent = msg; t.className = `show ${kind}`;
		clearTimeout(toastTimer);
		toastTimer = setTimeout(() => { t.className = ''; }, kind === 'err' ? 3500 : 1600);
	}
	const fail = (e) => { if (e.status !== 401) toast(e.message || String(e), 'err'); };
	const act = (p) => p.then(() => {}, fail);

	function haptic() { try { navigator.vibrate?.(8); } catch {} }

	// ---------------------------------------------------------------- login
	function showLogin() { $('#login').hidden = false; $('#app').hidden = true; stopLive(); }
	function showApp() { $('#login').hidden = true; $('#app').hidden = false; }
	$('#loginForm').addEventListener('submit', async (e) => {
		e.preventDefault();
		$('#loginError').textContent = '';
		try {
			await post('/api/login', { token: $('#tokenInput').value });
			$('#tokenInput').value = '';
			boot();
		} catch (err) { $('#loginError').textContent = err.message; }
	});
	$('#logoutBtn').addEventListener('click', () => act(post('/api/logout').then(showLogin)));

	// ---------------------------------------------------------------- tabs
	let currentTab = 'screen';
	function go(tab) {
		currentTab = tab;
		$$('.tab').forEach((t) => t.classList.toggle('active', t.dataset.tab === tab));
		$$('nav button').forEach((b) => b.classList.toggle('on', b.dataset.go === tab));
		try { localStorage.setItem('mr.tab', tab); } catch {}
		if (tab === 'screen') startLive(); else stopLive();
		if (tab === 'control') { refreshStatus(); loadApps(); }
		if (tab === 'files') loadFiles(filesPath);
	}
	$$('nav button').forEach((b) => b.addEventListener('click', () => go(b.dataset.go)));

	// ---------------------------------------------------------------- status
	const fmtBytes = (n) => (n >= 1e12 ? (n / 1e12).toFixed(2) + ' TB' : n >= 1e9 ? (n / 1e9).toFixed(1) + ' GB' : n >= 1e6 ? (n / 1e6).toFixed(0) + ' MB' : n >= 1e3 ? (n / 1e3).toFixed(0) + ' KB' : n + ' B');
	const fmtUptime = (s) => { const d = Math.floor(s / 86400), h = Math.floor((s % 86400) / 3600), m = Math.floor((s % 3600) / 60); return d ? `${d}d ${h}h` : h ? `${h}h ${m}m` : `${m}m`; };
	let screen = null;
	async function refreshStatus() {
		try {
			const s = await api('GET', '/api/status');
			$('#dot').className = 'dot on';
			$('#hostname').textContent = s.hostname.replace(/\.local$/, '');
			$('#front').textContent = s.frontApp ? `· ${s.frontApp}` : '';
			$('#uptime').textContent = 'up ' + fmtUptime(s.uptime);
			$('#cpu').textContent = s.cpu === null || s.cpu === undefined ? '—' : `${s.cpu}%`;
			$('#mem').textContent = `${fmtBytes(s.mem.total - s.mem.free)} / ${fmtBytes(s.mem.total)}`;
			$('#disk').textContent = s.disk ? `${fmtBytes(s.disk.used)} / ${fmtBytes(s.disk.total)}` : '—';
			$('#load').textContent = s.load.map((n) => n.toFixed(1)).join(' ');
			$('#screenSize').textContent = s.screen ? `${s.screen.w}×${s.screen.h}` : '—';
			$('#driver').textContent = s.capabilities.cliclick ? 'cliclick' : 'CoreGraphics';
			screen = s.screen;
			if (s.volume) setVolumeUI(s.volume);
			$('#nowPlaying').textContent = s.nowPlaying ? `${s.nowPlaying.state === 'playing' ? '▶' : '⏸'} ${s.nowPlaying.title} — ${s.nowPlaying.artist}` : '';
		} catch (e) { $('#dot').className = 'dot err'; fail(e); }
	}
	$('#refreshBtn').addEventListener('click', () => { refreshStatus(); if (currentTab === 'control') loadApps(); if (currentTab === 'files') loadFiles(filesPath); });
	setInterval(() => { if (!$('#app').hidden && document.visibilityState === 'visible' && currentTab !== 'screen') refreshStatus(); }, 15000);

	// ---------------------------------------------------------------- screen
	const stage = $('#stage'), shot = $('#shot'), hint = $('#stageHint');
	const LIVE = [0, 500, 1000, 2000], LIVE_LABEL = ['Off', '0.5s', '1s', '2s'];
	const QUAL = [{ w: 800, q: 45, l: 'Low' }, { w: 1280, q: 60, l: 'Med' }, { w: 1920, q: 72, l: 'High' }];
	let liveIdx = +(localStorage.getItem('mr.live') ?? 2), qualIdx = +(localStorage.getItem('mr.qual') ?? 1);
	let liveTimer = null, fetching = false, dragMode = false, lastShotAt = 0;

	async function grab() {
		if (fetching || document.visibilityState !== 'visible') return;
		fetching = true;
		const q = QUAL[qualIdx];
		const t0 = performance.now();
		try {
			const res = await api('GET', `/api/screen.jpg?w=${q.w}&q=${q.q}&t=${Date.now()}`, undefined, true);
			const blob = await res.blob();
			const url = URL.createObjectURL(blob);
			const old = shot.src;
			shot.onload = () => { shot.classList.add('ready'); hint.hidden = true; if (old.startsWith('blob:')) URL.revokeObjectURL(old); };
			shot.src = url;
			const dt = performance.now() - t0;
			$('#fps').textContent = `${Math.round(dt)} ms · ${fmtBytes(blob.size)}`;
			lastShotAt = Date.now();
			$('#dot').className = 'dot on';
		} catch (e) {
			if (e.status !== 401) { $('#fps').textContent = 'error'; hint.hidden = false; hint.firstElementChild.innerHTML = `<b>Screen capture failed</b>${escapeHtml(e.message)}`; }
			if (e.status === 401 || e.status >= 500) stopLive(true);
		} finally { fetching = false; }
	}
	function startLive() {
		stopLive(true);
		grab();
		if (LIVE[liveIdx]) liveTimer = setInterval(grab, LIVE[liveIdx]);
	}
	function stopLive(keepIdx) { clearInterval(liveTimer); liveTimer = null; }
	$('#liveBtn').addEventListener('click', () => { liveIdx = (liveIdx + 1) % LIVE.length; localStorage.setItem('mr.live', liveIdx); updateScreenBar(); startLive(); });
	$('#qualBtn').addEventListener('click', () => { qualIdx = (qualIdx + 1) % QUAL.length; localStorage.setItem('mr.qual', qualIdx); updateScreenBar(); grab(); });
	$('#dragBtn').addEventListener('click', () => { dragMode = !dragMode; updateScreenBar(); toast(dragMode ? 'Drag mode: swipe drags the mouse' : 'Swipe scrolls'); });
	$('#fsBtn').addEventListener('click', () => { document.body.classList.toggle('fs'); $('#fsBtn').textContent = document.body.classList.contains('fs') ? 'Exit full' : 'Fullscreen'; });
	function updateScreenBar() {
		$('#liveBtn').textContent = `Live: ${LIVE_LABEL[liveIdx]}`;
		$('#qualBtn').textContent = `Quality: ${QUAL[qualIdx].l}`;
		$('#dragBtn').classList.toggle('on', dragMode);
	}
	updateScreenBar();
	document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'visible' && currentTab === 'screen' && !$('#app').hidden) startLive(); else if (document.visibilityState !== 'visible') stopLive(true); });

	// Pointer gestures on the screenshot. Coordinates are normalized 0..1 relative to the image.
	function norm(e) {
		const r = shot.getBoundingClientRect();
		if (!r.width || !r.height) return null;
		return { x: Math.min(1, Math.max(0, (e.clientX - r.left) / r.width)), y: Math.min(1, Math.max(0, (e.clientY - r.top) / r.height)), cx: e.clientX, cy: e.clientY };
	}
	function ripple(cx, cy, right) {
		const r = stage.getBoundingClientRect();
		const el = document.createElement('div');
		el.className = 'ripple' + (right ? ' right' : '');
		el.style.left = cx - r.left + 'px'; el.style.top = cy - r.top + 'px';
		stage.appendChild(el);
		setTimeout(() => el.remove(), 500);
	}
	let gesture = null, clickTimer = null, lastTap = 0, scrollAcc = 0, scrollTimer = null;
	stage.addEventListener('pointerdown', (e) => {
		if (!shot.classList.contains('ready') || e.button !== 0) return;
		const p = norm(e); if (!p) return;
		stage.setPointerCapture(e.pointerId);
		gesture = { start: p, last: p, moved: false, id: e.pointerId, t: Date.now(), longPress: null };
		gesture.longPress = setTimeout(() => {
			if (!gesture || gesture.moved) return;
			gesture.done = true; haptic(); ripple(p.cx, p.cy, true);
			act(post('/api/mouse', { action: 'rightclick', x: p.x, y: p.y }));
		}, 550);
	});
	stage.addEventListener('pointermove', (e) => {
		if (!gesture || e.pointerId !== gesture.id) return;
		const p = norm(e); if (!p) return;
		const dx = p.cx - gesture.start.cx, dy = p.cy - gesture.start.cy;
		if (!gesture.moved && Math.hypot(dx, dy) > 10) { gesture.moved = true; clearTimeout(gesture.longPress); }
		if (!gesture.moved || gesture.done) return;
		if (!dragMode) {
			// Swipe = scroll. Roughly 40 px of finger travel per wheel line; positive dy = content moves down (finger down).
			scrollAcc += (p.cy - gesture.last.cy) / 40;
			gesture.last = p;
			if (!scrollTimer) scrollTimer = setTimeout(flushScroll, 90);
		} else gesture.last = p;
	});
	function flushScroll() {
		scrollTimer = null;
		const lines = Math.round(scrollAcc);
		if (!lines || !gesture) { scrollAcc = 0; return; }
		scrollAcc -= lines;
		act(post('/api/mouse', { action: 'scroll', dy: lines, dx: 0, x: gesture.start.x, y: gesture.start.y }));
	}
	function endGesture(e) {
		if (!gesture || e.pointerId !== gesture.id) return;
		const g = gesture; gesture = null;
		clearTimeout(g.longPress);
		if (g.done) return;
		if (g.moved) {
			if (dragMode) { ripple(g.last.cx, g.last.cy); act(post('/api/mouse', { action: 'drag', x: g.start.x, y: g.start.y, x2: g.last.x, y2: g.last.y })); }
			else if (scrollAcc) flushScroll();
			return;
		}
		const now = Date.now();
		if (now - lastTap < 300 && clickTimer) {
			clearTimeout(clickTimer); clickTimer = null; lastTap = 0;
			ripple(g.start.cx, g.start.cy);
			act(post('/api/mouse', { action: 'dblclick', x: g.start.x, y: g.start.y }));
			return;
		}
		lastTap = now;
		ripple(g.start.cx, g.start.cy);
		clickTimer = setTimeout(() => { clickTimer = null; act(post('/api/mouse', { action: 'click', x: g.start.x, y: g.start.y })); }, 220);
	}
	stage.addEventListener('pointerup', endGesture);
	stage.addEventListener('pointercancel', (e) => { if (gesture && e.pointerId === gesture.id) { clearTimeout(gesture.longPress); gesture = null; } });
	stage.addEventListener('contextmenu', (e) => e.preventDefault());

	// ---------------------------------------------------------------- keys
	const stickyMods = new Set();
	$$('#mods button').forEach((b) => b.addEventListener('click', () => {
		const m = b.dataset.mod;
		if (stickyMods.has(m)) stickyMods.delete(m); else stickyMods.add(m);
		b.classList.toggle('on', stickyMods.has(m));
	}));
	function consumeMods() {
		const mods = [...stickyMods];
		stickyMods.clear();
		$$('#mods button').forEach((b) => b.classList.remove('on'));
		return mods;
	}
	async function pressKey(key, mods) { haptic(); return post('/api/key', { key, mods }); }
	document.addEventListener('click', (e) => {
		const k = e.target.closest('[data-key]');
		if (k) return act(pressKey(k.dataset.key, consumeMods()));
		const s = e.target.closest('[data-shortcut]');
		if (s) return act(pressKey(s.dataset.shortcut, s.dataset.mods.split(',').filter(Boolean)));
		const m = e.target.closest('[data-media]');
		if (m) return act(post('/api/media', { action: m.dataset.media }).then((r) => { if (r.nowPlaying) $('#nowPlaying').textContent = `${r.nowPlaying.state === 'playing' ? '▶' : '⏸'} ${r.nowPlaying.title} — ${r.nowPlaying.artist}`; }));
		const p = e.target.closest('[data-power]');
		if (p) return power(p.dataset.power);
		const c = e.target.closest('[data-cmd]');
		if (c) { $('#cmd').value = c.dataset.cmd; runCmd(); }
	});
	$('#keyCharBtn').addEventListener('click', () => {
		const ch = $('#keyChar').value.trim();
		if (!ch) return toast('Type a letter first', 'err');
		act(pressKey(ch, consumeMods()));
	});
	$('#keyChar').addEventListener('keydown', (e) => { if (e.key === 'Enter') $('#keyCharBtn').click(); });
	async function typeText(withEnter) {
		const text = $('#typeText').value;
		if (!text && !withEnter) return;
		try {
			if (text) await post('/api/type', { text });
			if (withEnter) await post('/api/key', { key: 'return' });
			$('#typeText').value = '';
			toast('Typed', 'ok');
		} catch (e) { fail(e); }
	}
	$('#typeBtn').addEventListener('click', () => typeText(false));
	$('#typeEnterBtn').addEventListener('click', () => typeText(true));

	// ---------------------------------------------------------------- control
	function setVolumeUI(v) {
		if (v.level !== null) { $('#volume').value = v.level; $('#volLabel').textContent = v.muted ? 'mute' : `${v.level}%`; }
		$('#muteBtn').classList.toggle('on', Boolean(v.muted));
		$('#muteBtn').textContent = v.muted ? '🔇' : '🔊';
	}
	let volTimer;
	$('#volume').addEventListener('input', () => { $('#volLabel').textContent = `${$('#volume').value}%`; clearTimeout(volTimer); volTimer = setTimeout(() => act(post('/api/volume', { level: +$('#volume').value }).then(setVolumeUI)), 150); });
	$('#muteBtn').addEventListener('click', () => act(post('/api/volume', { muted: !$('#muteBtn').classList.contains('on') }).then(setVolumeUI)));

	async function power(action) {
		if (action === 'restart' || action === 'shutdown') {
			if (!confirm(`${action === 'restart' ? 'Restart' : 'Shut down'} the Mac? You will lose remote access until it is back${action === 'shutdown' ? ' (and someone presses the power button)' : ''}.`)) return;
			return act(post('/api/power', { action, confirm: true }).then(() => toast(`${action} sent`, 'ok')));
		}
		haptic();
		act(post('/api/power', { action }).then(() => { toast(action === 'wake' ? 'Display woken' : action === 'lock' ? 'Locked' : 'Sent', 'ok'); if (action === 'wake' && currentTab === 'screen') setTimeout(grab, 1200); }));
	}

	async function loadApps() {
		try {
			const { apps, front } = await api('GET', '/api/apps');
			const list = $('#apps');
			list.innerHTML = '';
			for (const name of apps) {
				const row = document.createElement('div');
				row.className = 'item' + (name === front ? ' front' : '');
				row.innerHTML = `<span class="ficon">${escapeHtml(name[0] || '?')}</span><span class="name"></span><button class="iconbtn" title="Quit"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M6 6l12 12M18 6L6 18"/></svg></button>`;
				row.querySelector('.name').textContent = name;
				row.querySelector('.name').addEventListener('click', () => act(post('/api/apps', { action: 'focus', name }).then(() => { toast(`${name} focused`, 'ok'); loadApps(); })));
				row.querySelector('.iconbtn').addEventListener('click', () => { if (confirm(`Quit ${name}?`)) act(post('/api/apps', { action: 'quit', name }).then(() => setTimeout(loadApps, 800))); });
				list.appendChild(row);
			}
			if (!apps.length) list.innerHTML = '<div class="muted">No apps</div>';
		} catch (e) { fail(e); }
	}
	$('#appsRefresh').addEventListener('click', loadApps);
	$('#appOpenBtn').addEventListener('click', () => { const name = $('#appName').value.trim(); if (name) act(post('/api/apps', { action: 'open', name }).then(() => { toast(`Opening ${name}`, 'ok'); $('#appName').value = ''; setTimeout(loadApps, 1500); })); });
	$('#appName').addEventListener('keydown', (e) => { if (e.key === 'Enter') $('#appOpenBtn').click(); });
	$('#urlOpenBtn').addEventListener('click', () => { let url = $('#urlInput').value.trim(); if (!url) return; if (!/^https?:\/\//i.test(url)) url = 'https://' + url; act(post('/api/open', { url }).then(() => { toast('Opened', 'ok'); $('#urlInput').value = ''; })); });
	$('#urlInput').addEventListener('keydown', (e) => { if (e.key === 'Enter') $('#urlOpenBtn').click(); });

	$('#clipGet').addEventListener('click', () => act(api('GET', '/api/clipboard').then((r) => { $('#clip').value = r.text; toast('Clipboard read', 'ok'); })));
	$('#clipSet').addEventListener('click', () => act(post('/api/clipboard', { text: $('#clip').value }).then(() => toast('Clipboard set', 'ok'))));
	$('#sayBtn').addEventListener('click', () => { const t = $('#sayText').value.trim(); if (t) act(post('/api/say', { text: t }).then(() => toast('Speaking…', 'ok'))); });
	$('#notifyBtn').addEventListener('click', () => { const t = $('#sayText').value.trim(); if (t) act(post('/api/notify', { title: 'Mac Remote', body: t }).then(() => toast('Notified', 'ok'))); });

	// ---------------------------------------------------------------- shell
	const out = $('#out'), cmdInput = $('#cmd');
	let history = []; try { history = JSON.parse(localStorage.getItem('mr.hist') || '[]'); } catch {}
	let histIdx = history.length;
	let shellCwd = '';
	function appendOut(text, cls) { const s = document.createElement('span'); if (cls) s.className = cls; s.textContent = text; out.appendChild(s); out.scrollTop = out.scrollHeight; }
	async function runCmd() {
		const cmd = cmdInput.value.trim();
		if (!cmd) return;
		cmdInput.value = '';
		history = [...history.filter((h) => h !== cmd), cmd].slice(-100); histIdx = history.length;
		try { localStorage.setItem('mr.hist', JSON.stringify(history)); } catch {}
		appendOut(`$ ${cmd}\n`, 'cmd');
		const cdMatch = /^cd(?:\s+(.*))?$/.exec(cmd);
		if (cdMatch) {
			const target = (cdMatch[1] || '').trim().replace(/^~\/?/, '');
			shellCwd = target === '' || target === '~' ? '' : target.startsWith('/') ? target.slice(1) : target === '..' ? shellCwd.split('/').slice(0, -1).join('/') : (shellCwd ? shellCwd + '/' : '') + target;
			$('#cwd').textContent = '~/' + shellCwd;
			return;
		}
		$('#runBtn').disabled = true;
		try {
			const r = await post('/api/shell', { cmd, cwd: shellCwd });
			if (r.stdout) appendOut(r.stdout.endsWith('\n') ? r.stdout : r.stdout + '\n');
			if (r.stderr) appendOut(r.stderr.endsWith('\n') ? r.stderr : r.stderr + '\n', 'err');
			if (r.code !== 0) appendOut(`[exit ${r.code}${r.killed ? ', timed out' : ''} · ${r.ms} ms]\n`, 'sys');
		} catch (e) { appendOut(`${e.message}\n`, 'err'); }
		finally { $('#runBtn').disabled = false; }
	}
	$('#runBtn').addEventListener('click', runCmd);
	cmdInput.addEventListener('keydown', (e) => {
		if (e.key === 'Enter') { e.preventDefault(); runCmd(); }
		else if (e.key === 'ArrowUp') { e.preventDefault(); $('#histPrev').click(); }
		else if (e.key === 'ArrowDown') { e.preventDefault(); $('#histNext').click(); }
	});
	$('#histPrev').addEventListener('click', () => { if (histIdx > 0) { histIdx--; cmdInput.value = history[histIdx]; cmdInput.focus(); } });
	$('#histNext').addEventListener('click', () => { if (histIdx < history.length - 1) { histIdx++; cmdInput.value = history[histIdx]; } else { histIdx = history.length; cmdInput.value = ''; } cmdInput.focus(); });
	$('#clearOut').addEventListener('click', () => { out.innerHTML = ''; });

	// ---------------------------------------------------------------- files
	let filesPath = '';
	const FILE_ICON = (name) => { const ext = name.split('.').pop().toLowerCase(); return /^(png|jpe?g|gif|heic|webp|svg)$/.test(ext) ? '🖼' : /^(mp4|mov|mkv|m4v)$/.test(ext) ? '🎬' : /^(mp3|m4a|wav|aac|flac)$/.test(ext) ? '🎵' : /^(pdf)$/.test(ext) ? '📕' : /^(zip|dmg|tar|gz|7z)$/.test(ext) ? '🗜' : /^(txt|md|json|js|ts|py|sh|html|css|log)$/.test(ext) ? '📝' : '📄'; };
	async function loadFiles(p) {
		try {
			const r = await api('GET', `/api/files?path=${encodeURIComponent(p)}`);
			filesPath = r.path === '.' ? '' : r.path;
			const crumbs = $('#crumbs');
			crumbs.innerHTML = '';
			const parts = filesPath ? filesPath.split('/') : [];
			const mk = (label, target) => { const b = document.createElement('button'); b.className = 'btn sm'; b.textContent = label; b.addEventListener('click', () => loadFiles(target)); crumbs.appendChild(b); };
			mk('~', '');
			parts.forEach((part, i) => mk(part, parts.slice(0, i + 1).join('/')));
			const list = $('#files');
			list.innerHTML = '';
			if (!r.items.length) list.innerHTML = '<div class="muted">Empty folder</div>';
			for (const it of r.items) {
				const rel = (filesPath ? filesPath + '/' : '') + it.name;
				const row = document.createElement('div');
				row.className = 'item';
				row.innerHTML = `<span class="ficon ${it.dir ? 'dir' : ''}">${it.dir ? '📁' : FILE_ICON(it.name)}</span><span class="name"></span><span class="meta">${it.dir ? '' : fmtBytes(it.size)}</span><button class="iconbtn"><svg viewBox="0 0 24 24" fill="currentColor"><circle cx="5" cy="12" r="2"/><circle cx="12" cy="12" r="2"/><circle cx="19" cy="12" r="2"/></svg></button>`;
				row.querySelector('.name').textContent = it.name;
				row.querySelector('.name').addEventListener('click', () => it.dir ? loadFiles(rel) : window.open(`/api/files/download?path=${encodeURIComponent(rel)}&inline=1`, '_blank'));
				row.querySelector('.iconbtn').addEventListener('click', () => fileSheet(it, rel));
				list.appendChild(row);
			}
		} catch (e) { fail(e); }
	}
	function sheet(title, actions) {
		const s = $('#sheet');
		s.innerHTML = '';
		const panel = document.createElement('div'); panel.className = 'panel';
		const t = document.createElement('div'); t.className = 'title'; t.textContent = title; panel.appendChild(t);
		for (const a of actions) {
			const b = document.createElement('button'); b.className = 'btn' + (a.danger ? ' danger' : ''); b.textContent = a.label;
			b.addEventListener('click', () => { s.hidden = true; a.run(); });
			panel.appendChild(b);
		}
		const cancel = document.createElement('button'); cancel.className = 'btn soft'; cancel.textContent = 'Cancel'; cancel.addEventListener('click', () => { s.hidden = true; });
		panel.appendChild(cancel);
		s.appendChild(panel);
		s.hidden = false;
		s.onclick = (e) => { if (e.target === s) s.hidden = true; };
	}
	function fileSheet(it, rel) {
		const actions = [];
		if (!it.dir) {
			actions.push({ label: 'Open', run: () => window.open(`/api/files/download?path=${encodeURIComponent(rel)}&inline=1`, '_blank') });
			actions.push({ label: 'Download', run: () => { location.href = `/api/files/download?path=${encodeURIComponent(rel)}`; } });
		} else actions.push({ label: 'Open folder', run: () => loadFiles(rel) });
		actions.push({ label: 'Open on Mac', run: () => act(post('/api/shell', { cmd: `open -- "$HOME/${rel.replace(/(["$`\\])/g, '\\$1')}"` }).then(() => toast('Opened on Mac', 'ok'))) });
		actions.push({ label: 'Delete', danger: true, run: () => { if (confirm(`Delete ${it.name}? This cannot be undone.`)) act(post('/api/files/delete', { path: rel }).then(() => loadFiles(filesPath))); } });
		sheet(it.name, actions);
	}
	$('#mkdirBtn').addEventListener('click', () => { const name = prompt('Folder name'); if (name) act(post('/api/files/mkdir', { path: (filesPath ? filesPath + '/' : '') + name }).then(() => loadFiles(filesPath))); });
	$('#uploadBtn').addEventListener('click', () => $('#uploadInput').click());
	$('#uploadInput').addEventListener('change', async (e) => {
		for (const f of e.target.files) {
			toast(`Uploading ${f.name}…`);
			try { await api('POST', `/api/files/upload?path=${encodeURIComponent(filesPath)}&name=${encodeURIComponent(f.name)}`, f, false); }
			catch (err) { fail(err); }
		}
		e.target.value = '';
		toast('Upload done', 'ok');
		loadFiles(filesPath);
	});

	// ---------------------------------------------------------------- misc
	function escapeHtml(s) { return String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c])); }

	async function boot() {
		try {
			await api('GET', '/api/me');
			showApp();
			let tab = 'screen'; try { tab = localStorage.getItem('mr.tab') || 'screen'; } catch {}
			go(tab);
			refreshStatus();
		} catch (e) { if (e.status !== 401) fail(e); }
	}

	// Token in the URL fragment (from the login URL / QR code the server prints) logs in once and is scrubbed.
	const hashToken = /(?:^|[#&])token=([^&]+)/.exec(location.hash);
	if (hashToken) {
		history.replaceState(null, '', location.pathname);
		post('/api/login', { token: decodeURIComponent(hashToken[1]) }).then(boot, (e) => { $('#loginError').textContent = e.message; });
	} else boot();
})();
