/* Two renderings of the same graph: one for a terminal, one for a browser.
 *
 * The force simulation is about forty lines of arithmetic — repulsion between
 * every pair, a spring along every edge, a pull toward the middle, and a
 * cooling factor. That is the whole of what a layout library would give us
 * here, and this vault will never hold the tens of thousands of nodes where
 * the O(n^2) pass stops being instant.
 */

export function simulate(graph, opts) {
	opts = opts || {};
	const W = opts.width || 1200, H = opts.height || 800;
	const iterations = opts.iterations || 400;
	const nodes = graph.nodes.map((n, i) => {
		/* Seeded on a spiral rather than at random: the same vault then lays
		 * out the same way every time, so the picture you learn to read stays
		 * put between runs. */
		const a = i * 2.399963;
		const r = 8 * Math.sqrt(i + 1);
		return { ...n, x: W / 2 + r * Math.cos(a), y: H / 2 + r * Math.sin(a), vx: 0, vy: 0 };
	});
	const index = new Map(nodes.map((n) => [n.id, n]));
	const edges = graph.edges.map((e) => ({ ...e, a: index.get(e.from), b: index.get(e.to) })).filter((e) => e.a && e.b);

	const repel = opts.repel || 5200;
	const springLen = opts.springLen || 62;
	const springK = 0.045;

	for (let step = 0; step < iterations; step++) {
		const cool = 1 - step / iterations;
		for (let i = 0; i < nodes.length; i++) {
			for (let j = i + 1; j < nodes.length; j++) {
				const a = nodes[i], b = nodes[j];
				let dx = b.x - a.x, dy = b.y - a.y;
				let d2 = dx * dx + dy * dy;
				if (d2 < 0.01) { dx = (i - j) * 0.1 + 0.05; dy = 0.05; d2 = dx * dx + dy * dy; }
				const d = Math.sqrt(d2);
				const f = repel / d2;
				const fx = (dx / d) * f, fy = (dy / d) * f;
				a.vx -= fx; a.vy -= fy;
				b.vx += fx; b.vy += fy;
			}
		}
		for (const e of edges) {
			const dx = e.b.x - e.a.x, dy = e.b.y - e.a.y;
			const d = Math.sqrt(dx * dx + dy * dy) || 0.01;
			const f = (d - springLen) * springK;
			const fx = (dx / d) * f, fy = (dy / d) * f;
			e.a.vx += fx; e.a.vy += fy;
			e.b.vx -= fx; e.b.vy -= fy;
		}
		for (const n of nodes) {
			n.vx += (W / 2 - n.x) * 0.0016;
			n.vy += (H / 2 - n.y) * 0.0016;
			n.x += n.vx * cool * 0.5;
			n.y += n.vy * cool * 0.5;
			n.vx *= 0.82; n.vy *= 0.82;
		}
	}
	return { nodes, edges: graph.edges, width: W, height: H };
}

/* An indented tree of what one note touches. Deliberately not an attempt to
 * draw a graph in text — a terminal renders hierarchy well and arbitrary
 * graphs badly, so this answers "what is this connected to" instead. */
export function asciiTree(notes, title, depth) {
	const byTitle = new Map(notes.map((n) => [n.title.toLowerCase(), n]));
	const back = new Map();
	notes.forEach((n) => n.links.forEach((l) => {
		const k = l.toLowerCase();
		if (!back.has(k)) back.set(k, []);
		back.get(k).push(n.title);
	}));
	const lines = [];
	const seen = new Set([String(title).toLowerCase()]);
	const root = byTitle.get(String(title).toLowerCase());
	lines.push(root ? root.title : title + '  (not written yet)');

	const walk = (t, prefix, level) => {
		if (level > depth) return;
		const note = byTitle.get(t.toLowerCase());
		const out = (note ? note.links : []).map((l) => ({ title: l, dir: '→' }));
		const inc = (back.get(t.toLowerCase()) || []).map((l) => ({ title: l, dir: '←' }));
		const kids = out.concat(inc).filter((k) => !seen.has(k.title.toLowerCase()));
		kids.forEach((k, i) => {
			const last = i === kids.length - 1;
			seen.add(k.title.toLowerCase());
			const exists = byTitle.has(k.title.toLowerCase());
			lines.push(prefix + (last ? '└── ' : '├── ') + k.dir + ' ' + k.title + (exists ? '' : '  (not written yet)'));
			walk(k.title, prefix + (last ? '    ' : '│   '), level + 1);
		});
	};
	walk(title, '', 1);
	return lines.join('\n');
}

const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

/* One self-contained file: no CDN, no fonts, nothing to fetch. It has to open
 * from a file:// URL on a laptop with no network. */
export function toHtml(graph, meta) {
	const laid = simulate(graph, { width: 1400, height: 950, iterations: 500 });
	/* Bounds from the nodes alone. Folding 0 into the minimum pinned the frame's
	 * top-left to the origin no matter where the graph actually settled, which
	 * left the drawing shoved into a corner of a mostly empty page. */
	const pad = 70;
	const xs = laid.nodes.map((n) => n.x), ys = laid.nodes.map((n) => n.y);
	const minX = Math.min(...xs) - pad, maxX = Math.max(...xs) + pad;
	const minY = Math.min(...ys) - pad, maxY = Math.max(...ys) + pad;
	const byId = new Map(laid.nodes.map((n) => [n.id, n]));
	const radius = (n) => (n.kind === 'folder' ? 7 : n.kind === 'unresolved' ? 3 : 4 + Math.min(6, n.deg * 0.7));

	const edgeSvg = laid.edges.map((e) => {
		const a = byId.get(e.from), b = byId.get(e.to);
		if (!a || !b) return '';
		return '<line x1="' + a.x.toFixed(1) + '" y1="' + a.y.toFixed(1) + '" x2="' + b.x.toFixed(1) + '" y2="' + b.y.toFixed(1) + '" class="e ' + e.kind + '" />';
	}).join('');

	const nodeSvg = laid.nodes.map((n) =>
		'<g class="n ' + n.kind + '" data-title="' + esc(n.title) + '">' +
		'<circle cx="' + n.x.toFixed(1) + '" cy="' + n.y.toFixed(1) + '" r="' + radius(n).toFixed(1) + '" />' +
		'<text x="' + n.x.toFixed(1) + '" y="' + (n.y + radius(n) + 11).toFixed(1) + '">' + esc(n.title) + '</text>' +
		'</g>').join('');

	const counts = laid.nodes.reduce((a, n) => { a[n.kind] = (a[n.kind] || 0) + 1; return a; }, {});

	return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<title>${esc(meta && meta.title ? meta.title : 'Jarvis vault')} — graph</title>
<style>
	* { box-sizing: border-box; }
	html, body { height: 100%; margin: 0; }
	body {
		background: #262624; color: #faf9f7; overflow: hidden;
		font: 13px/1.5 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
	}
	header {
		position: fixed; top: 0; left: 0; right: 0; z-index: 2;
		display: flex; align-items: center; gap: 14px; padding: 12px 18px;
		background: rgba(38, 38, 36, 0.82); border-bottom: 1px solid rgba(255, 255, 255, 0.09);
		backdrop-filter: blur(10px); -webkit-backdrop-filter: blur(10px);
	}
	header b { font-size: 14px; }
	header span { color: rgba(255, 255, 255, 0.55); }
	header input {
		margin-left: auto; background: rgba(255, 255, 255, 0.06); border: 1px solid rgba(255, 255, 255, 0.12);
		border-radius: 999px; color: inherit; font: inherit; padding: 6px 14px; width: 220px;
	}
	header input:focus { outline: none; border-color: #dd8163; }
	svg { width: 100vw; height: 100vh; display: block; cursor: grab; }
	svg:active { cursor: grabbing; }
	.e { stroke: rgba(255, 255, 255, 0.16); stroke-width: 1; }
	.e.folder { stroke: rgba(255, 255, 255, 0.09); }
	.n circle { fill: #d8d4c8; transition: fill 0.15s ease, r 0.15s ease; }
	.n.folder circle { fill: #dd8163; }
	.n.unresolved circle { fill: none; stroke: rgba(255, 255, 255, 0.42); stroke-width: 1.2; }
	.n text {
		fill: rgba(255, 255, 255, 0.62); font-size: 9px; text-anchor: middle;
		pointer-events: none; paint-order: stroke; stroke: rgba(0, 0, 0, 0.55); stroke-width: 2.4px;
	}
	.n.folder text { fill: #f0a077; font-weight: 600; font-size: 10px; }
	.n:hover circle { fill: #fff; }
	.n:hover text { fill: #fff; }
	.n.dim { opacity: 0.12; }
	.e.dim { opacity: 0.05; }
	footer {
		position: fixed; bottom: 0; left: 0; right: 0; z-index: 2; padding: 9px 18px;
		color: rgba(255, 255, 255, 0.42); font-size: 11.5px;
		background: rgba(38, 38, 36, 0.82); border-top: 1px solid rgba(255, 255, 255, 0.09);
		backdrop-filter: blur(10px); -webkit-backdrop-filter: blur(10px);
	}
	@media (prefers-color-scheme: light) {
		body { background: #faf9f7; color: #1f1e1d; }
		header, footer { background: rgba(250, 249, 247, 0.85); border-color: rgba(31, 30, 29, 0.1); }
		header span, footer { color: rgba(63, 60, 56, 0.72); }
		.e { stroke: rgba(31, 30, 29, 0.18); }
		.e.folder { stroke: rgba(31, 30, 29, 0.1); }
		.n circle { fill: #57534e; }
		.n.folder circle { fill: #b65334; }
		.n.unresolved circle { fill: none; stroke: rgba(31, 30, 29, 0.4); }
		.n text { fill: rgba(63, 60, 56, 0.78); stroke: rgba(250, 249, 247, 0.8); }
		.n.folder text { fill: #b65334; }
		.n:hover circle, .n:hover text { fill: #1f1e1d; }
	}
</style>
</head>
<body>
<header>
	<b>${esc(meta && meta.title ? meta.title : 'Jarvis vault')}</b>
	<span>${counts.note || 0} notes · ${counts.folder || 0} folders · ${counts.unresolved || 0} not yet written · ${laid.edges.length} links</span>
	<input id="q" type="search" placeholder="Filter…" autocomplete="off" />
</header>
<svg id="g" viewBox="${minX.toFixed(0)} ${minY.toFixed(0)} ${(maxX - minX).toFixed(0)} ${(maxY - minY).toFixed(0)}">
	<g id="pan">${edgeSvg}${nodeSvg}</g>
</svg>
<footer>Scroll to zoom, drag to pan. Generated by <code>jarvis graph --open</code> — this file is a snapshot, re-run it after editing the vault.</footer>
<script>
(() => {
	const svg = document.getElementById('g');
	const vb = { x: ${minX.toFixed(0)}, y: ${minY.toFixed(0)}, w: ${(maxX - minX).toFixed(0)}, h: ${(maxY - minY).toFixed(0)} };
	const apply = () => svg.setAttribute('viewBox', vb.x + ' ' + vb.y + ' ' + vb.w + ' ' + vb.h);
	svg.addEventListener('wheel', (e) => {
		e.preventDefault();
		const k = e.deltaY > 0 ? 1.12 : 0.89;
		const r = svg.getBoundingClientRect();
		const px = vb.x + ((e.clientX - r.left) / r.width) * vb.w;
		const py = vb.y + ((e.clientY - r.top) / r.height) * vb.h;
		vb.x = px - (px - vb.x) * k; vb.y = py - (py - vb.y) * k;
		vb.w *= k; vb.h *= k;
		apply();
	}, { passive: false });
	let drag = null;
	svg.addEventListener('pointerdown', (e) => { drag = { x: e.clientX, y: e.clientY }; svg.setPointerCapture(e.pointerId); });
	svg.addEventListener('pointermove', (e) => {
		if (!drag) return;
		const r = svg.getBoundingClientRect();
		vb.x -= (e.clientX - drag.x) * (vb.w / r.width);
		vb.y -= (e.clientY - drag.y) * (vb.h / r.height);
		drag = { x: e.clientX, y: e.clientY };
		apply();
	});
	const stop = () => { drag = null; };
	svg.addEventListener('pointerup', stop);
	svg.addEventListener('pointercancel', stop);

	const nodes = [...document.querySelectorAll('.n')];
	const edges = [...document.querySelectorAll('.e')];
	document.getElementById('q').addEventListener('input', (e) => {
		const q = e.target.value.trim().toLowerCase();
		if (!q) { nodes.forEach((n) => n.classList.remove('dim')); edges.forEach((l) => l.classList.remove('dim')); return; }
		nodes.forEach((n) => n.classList.toggle('dim', !n.dataset.title.toLowerCase().includes(q)));
		edges.forEach((l) => l.classList.add('dim'));
	});
})();
</script>
</body>
</html>
`;
}
