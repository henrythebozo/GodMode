/* The assistant half: what to tell the model about the vault, how to read what
 * it says back, and what its tool calls are allowed to do.
 *
 * Split out of jarvis.mjs so it can be exercised without spawning the binary —
 * the entry point runs main() on import, and a child process cannot always
 * reach a mock server anyway. jarvis.mjs is argument parsing and presentation;
 * everything here is the part with decisions in it.
 */
import path from 'node:path';
import * as V from './vault.mjs';
import * as P from './provider.mjs';

/* Which notes to put in front of the model.
 *
 * Term frequency with a rarity weight, a bonus for a hit in the title, and then
 * ONE HOP along the links out of whatever scored well. That last part is the
 * reason the graph exists: asking about Noah should also pull in the project
 * Noah's note points at, even when the question never names it.
 *
 * Not embeddings. Those need a model call per note and a vector store before
 * you can ask anything at all, and at the size a personal vault reaches they
 * pick the same handful this does. The seam is here if that changes. */
export function scoreNotes(notes, question) {
	const terms = String(question || '').toLowerCase().split(/[^a-z0-9]+/).filter((w) => w.length > 2);
	if (!terms.length) return [];
	/* A term in half the notes says nothing about which one you meant; one in a
	 * single note says everything. The useful half of a ranking function. */
	const rarity = {};
	terms.forEach((t) => {
		const hits = notes.filter((n) => (n.title + ' ' + n.body).toLowerCase().includes(t)).length;
		rarity[t] = hits ? Math.log(1 + notes.length / hits) : 0;
	});
	return notes.map((n) => {
		const title = n.title.toLowerCase(), body = n.body.toLowerCase();
		let score = 0;
		terms.forEach((t) => {
			if (title.includes(t)) score += 3 * rarity[t];
			if (body.includes(t)) score += rarity[t];
		});
		return { n, score };
	}).filter((x) => x.score > 0).sort((a, b) => b.score - a.score);
}
export function pickContext(notes, question, limit) {
	const ranked = scoreNotes(notes, question);
	const byTitle = new Map(notes.map((n) => [n.title.toLowerCase(), n]));
	const picked = [];
	const taken = new Set();
	const take = (n) => { if (n && !taken.has(n.file)) { taken.add(n.file); picked.push(n); } };
	ranked.slice(0, limit).forEach((x) => take(x.n));
	/* One hop out, from the strongest few only — expanding from everything
	 * would drag the whole vault back in and undo the point. */
	ranked.slice(0, 4).forEach((x) => x.n.links.forEach((l) => {
		if (picked.length < limit + 6) take(byTitle.get(l.toLowerCase()));
	}));
	/* Nothing matched: the notes touched most recently are a better guess than
	 * silence, because they are usually what you are in the middle of. */
	if (!picked.length) {
		notes.slice().sort((a, b) => String(b.updated).localeCompare(String(a.updated))).slice(0, 6).forEach(take);
	}
	return picked;
}

export function systemPrompt(cfg, notes) {
	const who = cfg.userName || 'the user';
	const lines = [
		'You are ' + cfg.assistantName + ', a dry, capable personal assistant running in ' + who + "'s terminal.",
		'Answer in plain text. No markdown headers, no bullet lists unless asked — this is a terminal, and short is better. One to four sentences unless real detail was requested.',
		'',
		'You have a memory vault of linked markdown notes. To act on it, output a fenced block shaped exactly like this and nothing else in the message:',
		'```jarvis-action',
		'{"tool": "remember", "args": {"fact": "...", "title": "...", "folder": "People", "links": ["Other Note"]}}',
		'```',
		'',
		'Tools:',
		'- remember {"fact": string, "title"?: string, "folder"?: string, "links"?: string[]} — write a new note. Use folders like People, Projects, Areas, Topics. Add links to notes it relates to.',
		'- link_notes {"from": string, "to": string} — link two notes both ways.',
		'- search_notes {"query": string} — find notes matching text.',
		'- get_note {"title": string} — read one note in full, with its backlinks.',
		'- get_time {} — the current date and time.',
		'',
		'For remember and link_notes, write a short spoken sentence alongside the block in the same message — the block is invisible to the user, so the sentence must stand alone.',
		'For search_notes, get_note and get_time, output ONLY the block; you will be given the result and can then answer.',
		'',
		'Vault index (' + notes.length + ' notes):',
	];
	const byFolder = {};
	notes.forEach((n) => { (byFolder[n.folder] = byFolder[n.folder] || []).push(n.title); });
	for (const [f, titles] of Object.entries(byFolder)) lines.push('  ' + f + ': ' + titles.join(', '));
	return lines.join('\n');
}

export function stripActions(text) {
	const actions = [];
	const cleaned = String(text).replace(/```jarvis-action\s*([\s\S]*?)```/g, (_, json) => {
		try { const a = JSON.parse(json.trim()); if (a && a.tool) actions.push(a); } catch {}
		return '';
	}).trim();
	return { actions, cleaned };
}

export function runVaultTool(cfg, vault, action) {
	const a = action.args || {};
	const notes = V.listNotes(vault);
	switch (action.tool) {
		case 'get_time':
			return { ok: true, message: new Date().toLocaleString() };
		case 'remember': {
			if (!a.fact) return { ok: false, message: 'No fact given.' };
			const links = Array.isArray(a.links) ? a.links : [];
			const body = a.fact + (links.length ? '\n\nRelated: ' + links.map((l) => '[[' + l + ']]').join(', ') : '');
			const file = V.writeNote(vault, { title: a.title || V.titleFrom(a.fact), folder: a.folder || V.DEFAULT_FOLDER, body });
			return { ok: true, message: 'Saved ' + path.relative(vault, file) };
		}
		case 'link_notes': {
			const from = V.findNote(vault, a.from);
			if (!from) return { ok: false, message: 'No note matches "' + a.from + '".' };
			const to = V.findLoose(vault, a.to);   // title only — see findNote in vault.mjs
			V.addLink(vault, from, to ? to.title : a.to);
			if (to) V.addLink(vault, V.readNote(to.file, vault), from.title);
			return { ok: true, message: 'Linked ' + from.title + ' ↔ ' + (to ? to.title : a.to) };
		}
		case 'search_notes': {
			const q = String(a.query || '').toLowerCase();
			const hits = notes.filter((n) => (n.title + ' ' + n.body).toLowerCase().includes(q)).slice(0, 12);
			return { ok: true, message: hits.length ? hits.map((n) => n.folder + '/' + n.title + ': ' + n.body.slice(0, 120)).join('\n') : 'No notes match "' + a.query + '".' };
		}
		case 'get_note': {
			const n = V.findNote(vault, a.title);
			if (!n) return { ok: false, message: 'No note called "' + a.title + '".' };
			const back = V.backlinks(notes, n.title).map((b) => b.title);
			return { ok: true, message: n.title + ' (' + n.folder + ')\n' + n.body + (back.length ? '\nLinked from: ' + back.join(', ') : '') };
		}
		default:
			return { ok: false, message: 'Unknown tool "' + action.tool + '".' };
	}
}

/* Output goes through an injectable `io` rather than straight to the terminal.
 * That is what lets a test drive a whole turn — prompt assembly, streaming,
 * the tool loop, the follow-up — and read back exactly what a user would have
 * seen, without a subprocess or a TTY. jarvis.mjs supplies the coloured one. */
export const PLAIN_IO = {
	write: (s) => process.stdout.write(s),
	clearLine: () => process.stdout.write('\r\u001b[2K'),
	tool: (okFlag, tool, message) => console.log((okFlag ? '  ok ' : '  !! ') + tool + ' · ' + message.split('\n')[0]),
	meta: (s) => { if (process.stdout.isTTY) console.log('  ' + s); },
	stopped: () => console.log('\nstopped'),
	fail: (msg) => { console.error('error: ' + msg); process.exitCode = 1; },
};

export function buildMessages(cfg, notes, question, opts) {
	opts = opts || {};
	const messages = [{ role: 'system', content: systemPrompt(cfg, notes) }];
	if (notes.length) {
		const picked = pickContext(notes, question, cfg.maxContextNotes);
		if (picked.length) {
			messages.push({
				role: 'system',
				content: 'Notes that look relevant:\n\n' + picked.map((n) => '## ' + n.title + ' (' + n.folder + ')\n' + n.body).join('\n\n'),
			});
		}
	}
	if (opts.extraContext) messages.push({ role: 'system', content: opts.extraContext });
	messages.push({ role: 'user', content: question });
	return messages;
}

export async function runTurn(cfg, question, opts) {
	opts = opts || {};
	const io = opts.io || PLAIN_IO;
	const vault = cfg.vault;
	const model = opts.model || cfg.model;
	const notes = opts.noMemory ? [] : V.listNotes(vault);
	const messages = buildMessages(cfg, notes, question, opts);

	/* Ctrl-C stops the request, not the process, so a runaway answer can be cut
	 * off without losing the shell you were working in. A second one really does
	 * quit, because at that point you mean it. */
	const ac = new AbortController();
	let stopped = false;
	const onSig = () => { if (stopped) process.exit(130); stopped = true; ac.abort(); };
	if (opts.signals !== false) process.on('SIGINT', onSig);
	const offSig = () => { if (opts.signals !== false) process.off('SIGINT', onSig); };

	let wrote = false;
	let res;
	try {
		res = await P.stream(model, messages, cfg, (delta) => { wrote = true; io.write(delta); }, ac.signal);
	} catch (err) {
		offSig();
		if (stopped || (err && err.name === 'AbortError')) { io.stopped(); return null; }
		io.fail(err && err.message ? err.message : String(err));
		return null;
	}
	offSig();

	const spent = P.recordUsage(vault, model, res.usage.in, res.usage.out);
	const { actions, cleaned } = stripActions(res.text);

	/* The stream may have carried an action block, which is meant to be
	 * invisible. Wipe the line and reprint only the prose. */
	if (actions.length && wrote) {
		io.clearLine();
		if (cleaned) io.write(cleaned);
	}
	if (wrote || cleaned) io.write('\n');

	for (const action of actions) {
		const out = runVaultTool(cfg, vault, action);
		io.tool(out.ok, action.tool, out.message);
		/* A lookup tool has no answer of its own, so its result is handed back
		 * for one more turn — and exactly one, so a model that keeps reaching
		 * for tools cannot spend your money in a loop. */
		if (!cleaned && LOOKUP_TOOLS.includes(action.tool) && !opts.depth) {
			messages.push({ role: 'assistant', content: res.text });
			messages.push({ role: 'user', content: '[Result of ' + action.tool + ']\n' + out.message + '\n\nAnswer now, in plain sentences, with no further tool calls.' });
			const follow = await P.stream(model, messages, cfg, (d) => io.write(d));
			P.recordUsage(vault, model, follow.usage.in, follow.usage.out);
			io.write('\n');
		}
	}

	if (spent && !opts.quiet) io.meta(fmtTokens(spent.in) + ' in · ' + fmtTokens(spent.out) + ' out · ' + fmtCost(spent.cost) + ' · ' + model);
	return res.text;
}

const LOOKUP_TOOLS = ['search_notes', 'get_note', 'get_time'];
function fmtTokens(n) { return n >= 1000 ? (n / 1000).toFixed(1) + 'k' : String(n); }
function fmtCost(x) {
	if (x === null || x === undefined) return 'price unknown';
	if (x === 0) return '$0.00';
	return '$' + (x < 0.01 ? x.toFixed(4) : x.toFixed(x < 1 ? 3 : 2));
}
