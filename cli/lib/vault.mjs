/* The vault: plain markdown files in plain folders.
 *
 * The format is deliberately Obsidian's, not one of our own, so the same
 * directory opens in Obsidian's graph view with no conversion and no plugin.
 * That means: one file per note, YAML frontmatter at the top, and [[Wikilinks]]
 * in the body.
 *
 * Links are NOT stored in the frontmatter. They are parsed out of the body
 * every time, which is what keeps them honest — edit a note in Obsidian, in
 * vim, or through this CLI and the graph comes out the same, because there is
 * only ever one copy of the truth and it is the prose.
 */
import fs from 'node:fs';
import path from 'node:path';

export const DEFAULT_FOLDER = 'Notes';

/* Windows forbids more of these than POSIX does, and a vault is meant to be
 * portable, so the stricter set applies everywhere. */
export function slug(title) {
	return String(title).replace(/[\\/:*?"<>|]/g, '-').replace(/\s+/g, ' ').trim().slice(0, 120) || 'untitled';
}

export function titleFrom(text) {
	const t = String(text || '').replace(/\s+/g, ' ').trim();
	if (!t) return 'Untitled';
	const firstSentence = t.split(/(?<=[.!?])\s/)[0];
	const base = firstSentence.length <= 60 ? firstSentence : t.slice(0, 60);
	return base.replace(/[.!?]+$/, '').trim() || 'Untitled';
}

export function stripCode(body) {
	return String(body || '').replace(/```[\s\S]*?```/g, ' ').replace(/`[^`\n]*`/g, ' ');
}
export function parseLinks(body) {
	/* Code comes out first. Obsidian does the same, and without it any note
	 * that TALKS about linking — a readme, a snippet, anything quoting the
	 * syntax — invents nodes in the graph that nobody meant to create. */
	const text = stripCode(body);
	const out = [];
	const re = /\[\[([^\]|#]+)(?:[|#][^\]]*)?\]\]/g;
	let m;
	while ((m = re.exec(text))) {
		const t = m[1].trim();
		if (t && !out.includes(t)) out.push(t);
	}
	return out;
}

/* A hand-rolled reader for exactly the frontmatter this tool writes, rather
 * than a YAML dependency: scalars and one flow list. */
function parseFrontmatter(text) {
	if (!text.startsWith('---\n')) return { meta: {}, body: text };
	const end = text.indexOf('\n---', 3);
	if (end < 0) return { meta: {}, body: text };
	const raw = text.slice(4, end);
	const body = text.slice(end + 4).replace(/^\n/, '');
	const meta = {};
	for (const line of raw.split('\n')) {
		const m = line.match(/^([A-Za-z0-9_-]+):\s*(.*)$/);
		if (!m) continue;
		let v = m[2].trim();
		if (v.startsWith('[') && v.endsWith(']')) {
			v = v.slice(1, -1).split(',').map((s) => s.trim().replace(/^["']|["']$/g, '')).filter(Boolean);
		} else {
			v = v.replace(/^["']|["']$/g, '');
		}
		meta[m[1]] = v;
	}
	return { meta, body };
}

function buildFrontmatter(meta) {
	const lines = ['---'];
	for (const [k, v] of Object.entries(meta)) {
		if (v === undefined || v === null || v === '') continue;
		lines.push(k + ': ' + (Array.isArray(v) ? '[' + v.join(', ') + ']' : String(v)));
	}
	lines.push('---');
	return lines.join('\n');
}

export function ensureVault(dir) {
	fs.mkdirSync(dir, { recursive: true });
	fs.mkdirSync(path.join(dir, '.jarvis'), { recursive: true });
	return dir;
}

function walk(dir, out) {
	let entries = [];
	try { entries = fs.readdirSync(dir, { withFileTypes: true }); } catch { return out; }
	for (const e of entries) {
		if (e.name.startsWith('.')) continue;
		const full = path.join(dir, e.name);
		if (e.isDirectory()) walk(full, out);
		else if (e.name.endsWith('.md')) out.push(full);
	}
	return out;
}

function statMtime(file) {
	try { return fs.statSync(file).mtimeMs; } catch { return 0; }
}

export function readNote(file, vault) {
	const text = fs.readFileSync(file, 'utf8');
	const { meta, body } = parseFrontmatter(text);
	const rel = path.relative(vault, file);
	const dir = path.dirname(rel);
	const folder = dir === '.' ? '' : dir.split(path.sep)[0];
	return {
		file,
		title: meta.title || path.basename(file, '.md'),
		folder: meta.folder || folder || DEFAULT_FOLDER,
		tags: Array.isArray(meta.tags) ? meta.tags : (meta.tags ? [meta.tags] : []),
		created: meta.created || '',
		updated: meta.updated || '',
		/* `updated:` says when JARVIS last wrote the file. Obsidian, vim and
		 * every other editor change the body and leave the frontmatter alone,
		 * so on its own it makes an edit made elsewhere look like it never
		 * happened. mtime is the part nothing can forget to update; the larger
		 * of the two wins so a vault copied around by git still sorts sanely. */
		at: Math.max(Date.parse(meta.updated) || 0, statMtime(file)),
		body: body.trim(),
		links: parseLinks(body),
	};
}

export function listNotes(vault) {
	return walk(vault, []).map((f) => readNote(f, vault)).sort((a, b) => a.title.localeCompare(b.title));
}

/* Two lookups, and the difference matters. A [[wikilink]] resolves by TITLE
 * and nothing else: the loose search falls back to matching the body, and a
 * link's target text is itself part of a body, so resolving links that way
 * makes every unwritten link "resolve" to the note that mentioned it — and the
 * unresolved nodes vanish from the graph. The loose one is for what somebody
 * typed, where guessing is the helpful thing to do. */
export function findByTitle(vault, title) {
	const t = String(title || '').toLowerCase().trim();
	if (!t) return null;
	return listNotes(vault).find((n) => n.title.toLowerCase() === t) || null;
}
export function findLoose(vault, query) {
	const q = String(query || '').toLowerCase().trim();
	if (!q) return null;
	const notes = listNotes(vault);
	return notes.find((n) => n.title.toLowerCase() === q)
		|| notes.find((n) => n.title.toLowerCase().includes(q))
		|| null;
}
export function findNote(vault, query) {
	const q = String(query || '').toLowerCase().trim();
	if (!q) return null;
	return findLoose(vault, q) || listNotes(vault).find((n) => n.body.toLowerCase().includes(q)) || null;
}

/* Two different titles can slug to one filename — "A/B" and "A-B" both become
 * A-B.md, since the slash is not legal in a filename on Windows. Writing
 * straight to that path silently destroyed whichever note got there first,
 * and reported success while doing it. A new note never overwrites an existing
 * file now; it takes the next free name instead, matching the web app. */
function freeFilename(dir, title) {
	const base = slug(title);
	let name = base, i = 2;
	while (fs.existsSync(path.join(dir, name + '.md'))) name = base + ' (' + i++ + ')';
	return path.join(dir, name + '.md');
}

export function writeNote(vault, note) {
	const folder = note.folder || DEFAULT_FOLDER;
	const dir = path.join(vault, folder);
	fs.mkdirSync(dir, { recursive: true });
	const file = note.file || freeFilename(dir, note.title);
	const now = new Date().toISOString();
	const meta = { title: note.title, folder, created: note.created || now, updated: now };
	if (note.tags && note.tags.length) meta.tags = note.tags;
	fs.writeFileSync(file, buildFrontmatter(meta) + '\n\n' + String(note.body || '').trim() + '\n', 'utf8');
	return file;
}

export function removeNote(note) {
	fs.unlinkSync(note.file);
	return note.file;
}

/* Adds a [[link]] to a note's body if it is not already there. It is appended
 * to the PROSE rather than to a metadata field, which is the whole point: the
 * link has to sit where a human reading the note would see it. */
export function addLink(vault, note, targetTitle) {
	if (note.links.some((l) => l.toLowerCase() === targetTitle.toLowerCase())) return false;
	const body = note.body.trim();
	const rel = body.match(/^Related: .*$/m);
	const next = rel
		? body.replace(rel[0], rel[0] + ', [[' + targetTitle + ']]')
		: (body ? body + '\n\nRelated: [[' + targetTitle + ']]' : 'Related: [[' + targetTitle + ']]');
	writeNote(vault, { ...note, body: next });
	return true;
}

/* The graph the whole thing exists for.
 *
 * Three kinds of node, matching what Obsidian draws:
 *   note       — a file that exists
 *   unresolved — a [[Target]] nothing has created yet, which is a real part of
 *                the picture: it is the shape of what you have not written down
 *   folder     — the hubs. Without them a vault of lightly-linked notes renders
 *                as scattered dust, and the folders are structure you already
 *                chose, so they cost nothing to show.
 */
export function buildGraph(notes, opts) {
	opts = opts || {};
	const nodes = new Map();
	const edges = [];
	const key = (t) => String(t).toLowerCase();
	const addNode = (title, kind) => {
		const k = key(title);
		if (!nodes.has(k)) nodes.set(k, { id: k, title, kind, deg: 0 });
		else if (kind === 'note' && nodes.get(k).kind === 'unresolved') nodes.get(k).kind = 'note';
		return nodes.get(k);
	};
	const addEdge = (a, b, kind) => {
		if (key(a) === key(b)) return;
		const id = key(a) + ' ' + key(b);
		if (edges.some((e) => e.id === id)) return;
		edges.push({ id, from: key(a), to: key(b), kind });
		nodes.get(key(a)).deg++;
		nodes.get(key(b)).deg++;
	};
	notes.forEach((n) => addNode(n.title, 'note'));
	if (opts.folders !== false) notes.forEach((n) => { if (n.folder) addNode(n.folder, 'folder'); });
	notes.forEach((n) => {
		n.links.forEach((l) => { addNode(l, 'unresolved'); addEdge(n.title, l, 'link'); });
		if (opts.folders !== false && n.folder) addEdge(n.folder, n.title, 'folder');
	});
	return { nodes: [...nodes.values()], edges };
}

/* Links you have already written in prose without knowing it.
 *
 * A note saying "Noah is working on APEX" is describing an edge; it just has
 * not got the brackets. This finds those, which is the difference between a
 * graph that fills in over months and one that fills in this afternoon.
 *
 * Two rules keep it from being noise: a word boundary, so a title of "Work"
 * does not match inside "network"; and a floor on title length, because a
 * three-letter title matches everything and suggesting everything is the same
 * as suggesting nothing. */
export const SUGGEST_MIN_TITLE = 4;
export function suggestLinks(notes) {
	const out = [];
	const linksOf = new Map(notes.map((n) => [n.file, n.links.map((l) => l.toLowerCase())]));
	/* Code is stripped for the same reason parseLinks strips it: a title inside
	 * a snippet is a quotation, not a reference. Without this, the vault's own
	 * welcome note — which shows an example command naming a note — suggests a
	 * link to every note the examples happen to mention. */
	const proseOf = new Map(notes.map((n) => [n.file, stripCode(n.body)]));
	notes.forEach((from) => {
		notes.forEach((to) => {
			if (to.file === from.file) return;
			if (to.title.length < SUGGEST_MIN_TITLE) return;
			if (linksOf.get(from.file).includes(to.title.toLowerCase())) return;
			/* Either direction counts as already linked — offering the reverse
			 * of a link you have is asking the same question twice. */
			if (linksOf.get(to.file).includes(from.title.toLowerCase())) return;
			const re = new RegExp('(^|[^\\w\\[])' + to.title.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + '($|[^\\w\\]])', 'i');
			const prose = proseOf.get(from.file);
			if (!re.test(prose)) return;
			out.push({ from: from.title, to: to.title, where: excerptAround(prose, to.title) });
		});
	});
	return out;
}
function excerptAround(body, needle) {
	const i = body.toLowerCase().indexOf(needle.toLowerCase());
	if (i < 0) return body.slice(0, 70);
	const start = Math.max(0, i - 30);
	return (start ? '…' : '') + body.slice(start, i + needle.length + 40).replace(/\s+/g, ' ') + (i + needle.length + 40 < body.length ? '…' : '');
}

export function backlinks(notes, title) {
	const t = String(title).toLowerCase();
	return notes.filter((n) => n.links.some((l) => l.toLowerCase() === t));
}

/* Breadth-first neighbourhood around one note, for `jarvis graph <title>` and
 * for choosing what to put in the model's context. */
export function neighbourhood(notes, title, depth) {
	const byTitle = new Map(notes.map((n) => [n.title.toLowerCase(), n]));
	const back = new Map();
	notes.forEach((n) => n.links.forEach((l) => {
		const k = l.toLowerCase();
		if (!back.has(k)) back.set(k, []);
		back.get(k).push(n.title);
	}));
	const seen = new Map([[String(title).toLowerCase(), 0]]);
	const queue = [[String(title), 0]];
	const out = [];
	while (queue.length) {
		const [t, d] = queue.shift();
		const note = byTitle.get(t.toLowerCase());
		out.push({ title: note ? note.title : t, depth: d, exists: !!note });
		if (d >= (depth || 1)) continue;
		const next = ((note && note.links) || []).concat(back.get(t.toLowerCase()) || []);
		for (const n of next) {
			if (seen.has(n.toLowerCase())) continue;
			seen.set(n.toLowerCase(), d + 1);
			queue.push([n, d + 1]);
		}
	}
	return out;
}
