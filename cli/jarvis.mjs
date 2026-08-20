#!/usr/bin/env node
/* jarvis — Jarvis in the terminal.
 *
 * Zero dependencies on purpose. The web app is a single no-build HTML file and
 * this is its counterpart: Node built-ins only, so `git clone && npm link` is
 * the whole install and there is no lockfile to rot.
 *
 * The vault is the point. Memory is markdown on your disk, in folders you can
 * see, with [[wikilinks]] between notes — the same format Obsidian reads, so
 * the graph you get here and the graph you get there are the same graph.
 */
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import readline from 'node:readline';
import { spawn } from 'node:child_process';
import { loadConfig, saveConfig, CONFIG_PATH, SECRET_KEYS, redact } from './lib/config.mjs';
import * as V from './lib/vault.mjs';
import * as P from './lib/provider.mjs';
import * as G from './lib/graph.mjs';
import { runTurn } from './lib/agent.mjs';
import * as OAuth from './lib/oauth.mjs';

const args = process.argv.slice(2);
const useColor = process.stdout.isTTY && !process.env.NO_COLOR;
/* Written as \u001b rather than a raw ESC byte: a literal control character
 * in source makes the file look binary to git, to `file`, and to any tool
 * that sniffs before reading. */
const c = (code) => (s) => (useColor ? '\u001b[' + code + 'm' + s + '\u001b[0m' : String(s));
const bold = c('1'), dim = c('2'), accent = c('38;5;209'), ok = c('32'), bad = c('31');

function die(msg) { console.error(bad('✗ ') + msg); process.exit(1); }
function fmtTokens(n) { return n >= 1000 ? (n / 1000).toFixed(1) + 'k' : String(n); }
function fmtCost(x) {
	if (x === null || x === undefined) return '—';
	if (x === 0) return '$0.00';
	return '$' + (x < 0.01 ? x.toFixed(4) : x.toFixed(x < 1 ? 3 : 2));
}

const HELP = `
${bold('jarvis')} — ${dim('a linked markdown memory vault, and the assistant that reads it')}

  ${bold('jarvis')} "what's on my plate today"     ask a question
  ${bold('jarvis ask')} "..." [--model ID] [--no-memory]

  ${bold('jarvis login')}                           sign in with OpenRouter — no key to paste
  ${bold('jarvis logout')}                          forget the key on this machine
  ${bold('jarvis init')}                            create the vault and store a key
  ${bold('jarvis mem add')} "..." [-f Folder] [-t Title] [-l Other]
  ${bold('jarvis mem list')} [query]                list notes, newest first
  ${bold('jarvis mem show')} <title>                print one note and its backlinks
  ${bold('jarvis mem link')} <a> <b>                link two notes both ways
  ${bold('jarvis mem rm')} <title>                  delete a note
  ${bold('jarvis mem open')} <title>                open a note in $EDITOR
  ${bold('jarvis mem suggest')} [--apply]             links you wrote in prose without brackets

  ${bold('jarvis graph')} [title] [--depth N]       what is connected to what
  ${bold('jarvis graph --open')}                    render the whole vault and open it

  ${bold('jarvis chain list')}
  ${bold('jarvis chain run')} <name>
  ${bold('jarvis chain add')} <name> <step> [step…]  a step is a note: prompt

  ${bold('jarvis usage')}                           tokens and cost so far
  ${bold('jarvis config')} [key [value]]            show or set configuration
  ${bold('jarvis export')} [file]                   a backup the web app can import
  ${bold('jarvis import')} <file>                   pull a web-app backup into the vault

${dim('Keys are read from the environment first (ANTHROPIC_API_KEY, OPENAI_API_KEY,')}
${dim('OPENROUTER_API_KEY, GEMINI_API_KEY) and from ' + CONFIG_PATH + ' second.')}
${dim('Point baseUrl at any OpenAI-compatible server for a local model:')}
${dim('  jarvis config baseUrl http://localhost:11434/v1 && jarvis config model llama3.2')}
`;

/* -------------------------------- helpers -------------------------------- */

function flag(name, short) {
	const i = args.findIndex((a) => a === '--' + name || (short && a === '-' + short));
	if (i < 0) return null;
	const v = args[i + 1];
	if (v === undefined || v.startsWith('-')) return true;
	args.splice(i, 2);
	return v;
}
function hasFlag(name) {
	const i = args.indexOf('--' + name);
	if (i < 0) return false;
	args.splice(i, 1);
	return true;
}
function vaultOf(cfg) {
	if (!fs.existsSync(cfg.vault)) {
		die('No vault at ' + cfg.vault + '. Run `jarvis init` first.');
	}
	return cfg.vault;
}
function ask(rl, q, fallback) {
	return new Promise((res) => rl.question(q, (a) => res(a.trim() || fallback || '')));
}
function openExternally(file) {
	const cmd = process.platform === 'darwin' ? 'open' : process.platform === 'win32' ? 'start' : 'xdg-open';
	try {
		const p = spawn(cmd, [file], { stdio: 'ignore', detached: true, shell: process.platform === 'win32' });
		p.on('error', () => {});
		p.unref();
		return true;
	} catch { return false; }
}

/* The agent writes through this rather than to stdout directly, so colour and
 * layout stay here in the presentation layer and lib/agent.mjs stays testable. */
const io = {
	write: (s) => process.stdout.write(s),
	clearLine: () => process.stdout.write('\r\u001b[2K'),
	tool: (okFlag, tool, message) => console.log((okFlag ? ok('  ✓ ') : bad('  ✗ ')) + dim(tool + ' · ') + message.split('\n')[0]),
	meta: (s) => { if (process.stdout.isTTY) console.log(dim('  ' + s)); },
	stopped: () => console.log('\n' + dim('stopped')),
	fail: (msg) => die(msg),
};
function turn(cfg, question, opts) {
	vaultOf(cfg);
	return runTurn(cfg, question, { io, ...(opts || {}) });
}

/* -------------------------------- login ---------------------------------- */

/* A `gpt:` / `claude:` / `gemini:` model id means "go straight to that vendor
 * with that vendor's key", which an OpenRouter key cannot do. Signing in and
 * then failing on the first question because the lead model still points
 * somewhere the new key has no business would be a strange welcome. Anything
 * already routed through OpenRouter is left exactly as it is. */
function leadModelForOpenRouter(cfg) {
	if (/^(gpt|claude|gemini):/.test(cfg.model || '')) cfg.model = 'anthropic/claude-sonnet-5';
}

async function cmdLogin(cfg) {
	const manual = hasFlag('manual');
	if (cfg.key) console.log(dim('Replacing the OpenRouter key already on this machine (' + redact(cfg.key) + ').\n'));

	const verifier = OAuth.makeVerifier();
	const challenge = OAuth.challengeFor(verifier);

	/* No loopback server, for a machine with no browser — a remote shell, a
	 * container, anything over ssh. OpenRouter shows the key on screen and you
	 * paste it once; still better than hunting through the dashboard. */
	if (manual) {
		console.log('Open this on any device, then paste the key it shows you:\n');
		console.log('  ' + accent('https://openrouter.ai/auth?key_label=' + encodeURIComponent('Jarvis CLI')) + '\n');
		const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
		const key = await ask(rl, 'Key: ', '');
		rl.close();
		if (!key) die('Nothing pasted.');
		cfg.key = key;
		cfg.keySource = 'openrouter-manual';
		leadModelForOpenRouter(cfg);
		saveConfig(cfg);
		console.log(ok('✓') + ' Saved to ' + CONFIG_PATH + dim(' (0600)'));
		return;
	}

	let code;
	try {
		code = await OAuth.waitForCode({
			onReady: (port, callback) => {
				const url = OAuth.authUrl(callback, challenge);
				console.log('Opening OpenRouter in your browser…');
				console.log(dim('  If nothing opens, go to:\n  ' + url + '\n'));
				OAuth.openBrowser(url);
				console.log(dim('  Waiting on 127.0.0.1:' + port + ' — Ctrl-C to give up.'));
			},
		});
	} catch (err) {
		die((err && err.message ? err.message : String(err)));
	}

	let key;
	try { key = await OAuth.exchangeCode(code, verifier); }
	catch (err) { die('Could not exchange the code: ' + (err && err.message ? err.message : err)); }

	cfg.key = key;
	cfg.keySource = 'openrouter-oauth';
	leadModelForOpenRouter(cfg);
	saveConfig(cfg);
	console.log('\n' + ok('✓') + ' Signed in. Key saved to ' + CONFIG_PATH + dim(' (0600)'));
	console.log(dim('  Claude, Gemini and GPT all run through OpenRouter — `jarvis config model <id>` to switch.\n'));
}

function cmdLogout(cfg) {
	if (!cfg.key) { console.log(dim('Not signed in.')); return; }
	cfg.key = '';
	cfg.keySource = '';
	saveConfig(cfg);
	console.log(ok('✓') + ' Forgotten on this machine.');
	console.log(dim('  Your OpenRouter account is untouched — revoke the key at openrouter.ai/keys if you want it dead.'));
}

/* --------------------------------- init ---------------------------------- */

function writeWelcome(vault) {
	if (fs.existsSync(path.join(vault, 'Welcome.md'))) return;
	V.writeNote(vault, {
		title: 'Welcome', folder: 'Notes',
		body: 'This is your Jarvis vault. Every note is a plain markdown file, so this folder\n' +
			'opens in Obsidian as-is — point Obsidian at it and its graph view shows the same\n' +
			'picture `jarvis graph --open` does.\n\n' +
			'Link notes by wrapping a title in double square brackets. A link to something you\n' +
			'have not written yet is fine, and shows up in the graph as a hollow node — the\n' +
			'shape of what you have not got round to.\n\n' +
			'Try: `jarvis mem add "Noah starts school Sept 3" -f People -t Noah`\n' +
			'Then: `jarvis graph Noah`',
	});
}

const PROVIDERS = [
	{ n: '1', label: 'Anthropic (Claude)', field: 'anthKey', prefix: 'sk-ant-', model: 'claude:claude-sonnet-5', where: 'console.anthropic.com' },
	{ n: '2', label: 'OpenAI (GPT)', field: 'oaiKey', prefix: 'sk-', model: 'gpt:gpt-4o', where: 'platform.openai.com/api-keys' },
	{ n: '3', label: 'OpenRouter (many models, one key)', field: 'key', prefix: 'sk-or-', model: 'anthropic/claude-sonnet-5', where: 'openrouter.ai/keys' },
	{ n: '4', label: 'Google Gemini', field: 'geminiKey', prefix: 'AI', model: 'gemini:gemini-2.5-flash', where: 'aistudio.google.com/apikey' },
];

async function cmdInit(cfg) {
	/* --yes takes every default without asking, which is what makes this
	 * usable from a dotfiles script or CI. It is also the only way to exercise
	 * init in a test, since prompts and a non-TTY stdin do not mix. */
	const unattended = hasFlag('yes') || !process.stdin.isTTY;
	if (unattended) {
		cfg.vault = path.resolve(String(flag('vault') || cfg.vault).replace(/^~(?=$|\/)/, os.homedir()));
		V.ensureVault(cfg.vault);
		for (const f of ['People', 'Projects', 'Areas', 'Topics']) fs.mkdirSync(path.join(cfg.vault, f), { recursive: true });
		writeWelcome(cfg.vault);
		saveConfig(cfg);
		console.log(ok('✓') + ' Vault ready at ' + cfg.vault);
		return;
	}
	const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
	console.log('\n' + bold('Setting up Jarvis.') + '\n');

	const vault = await ask(rl, 'Vault folder [' + cfg.vault + ']: ', cfg.vault);
	cfg.vault = path.resolve(vault.replace(/^~(?=$|\/)/, os.homedir()));

	console.log('\nWhich provider?');
	console.log('  ' + dim('0) Sign in with OpenRouter — no key to paste (recommended)'));
	PROVIDERS.forEach((p) => console.log('  ' + p.n + ') ' + p.label));
	const pick = await ask(rl, 'Choice [0]: ', '0');
	if (pick === '0') {
		rl.close();
		V.ensureVault(cfg.vault);
		for (const f of ['People', 'Projects', 'Areas', 'Topics']) fs.mkdirSync(path.join(cfg.vault, f), { recursive: true });
		writeWelcome(cfg.vault);
		saveConfig(cfg);
		console.log(ok('✓') + ' Vault ready at ' + bold(cfg.vault) + '\n');
		return cmdLogin(cfg);
	}
	const prov = PROVIDERS.find((p) => p.n === pick) || PROVIDERS[0];

	if (process.env[prov.field] || cfg[prov.field]) {
		console.log(dim('  A ' + prov.label + ' key is already set (' + redact(cfg[prov.field]) + ').'));
	}
	console.log(dim('  Create one at ' + prov.where + '. Leave blank to keep the current one.'));
	const key = await ask(rl, prov.label + ' key: ', '');
	if (key) {
		/* Shape-checked, never probed: a validation request would spend money
		 * before anyone agreed to anything, and the mistake that actually
		 * happens is pasting a different provider's key. */
		if (!key.startsWith(prov.prefix)) console.log(dim('  Note: ' + prov.label + ' keys usually start with "' + prov.prefix + '". Saving it anyway.'));
		cfg[prov.field] = key;
		cfg.model = prov.model;
	}

	cfg.userName = await ask(rl, 'What should Jarvis call you? [' + (cfg.userName || 'nothing in particular') + ']: ', cfg.userName);
	cfg.assistantName = await ask(rl, 'What should it be called? [' + cfg.assistantName + ']: ', cfg.assistantName);
	rl.close();

	V.ensureVault(cfg.vault);
	for (const f of ['People', 'Projects', 'Areas', 'Topics']) fs.mkdirSync(path.join(cfg.vault, f), { recursive: true });
	writeWelcome(cfg.vault);
	const saved = saveConfig(cfg);
	console.log('\n' + ok('✓') + ' Vault ready at ' + bold(cfg.vault));
	console.log(ok('✓') + ' Config written to ' + saved + dim(' (0600)'));
	console.log('\nTry: ' + accent('jarvis "remember that I prefer short answers"') + '\n');
}

/* -------------------------------- memory --------------------------------- */

function cmdMem(cfg, sub, rest) {
	const vault = vaultOf(cfg);
	if (sub === 'add') {
		const folder = flag('folder', 'f') || V.DEFAULT_FOLDER;
		const title = flag('title', 't');
		const links = [];
		for (;;) { const l = flag('link', 'l'); if (!l || l === true) break; links.push(l); }
		const text = rest.filter((a) => !a.startsWith('-')).join(' ').trim();
		if (!text) die('Nothing to remember. `jarvis mem add "..."`');
		const body = text + (links.length ? '\n\nRelated: ' + links.map((l) => '[[' + l + ']]').join(', ') : '');
		const file = V.writeNote(vault, { title: title === true || !title ? V.titleFrom(text) : title, folder: folder === true ? V.DEFAULT_FOLDER : folder, body });
		console.log(ok('✓') + ' ' + path.relative(vault, file));
		links.forEach((l) => console.log(dim('  ↔ ' + l)));
		return;
	}
	if (sub === 'list' || !sub) {
		const q = rest.join(' ').toLowerCase().trim();
		let notes = V.listNotes(vault);
		if (q) notes = notes.filter((n) => (n.title + ' ' + n.body).toLowerCase().includes(q));
		if (!notes.length) return console.log(dim(q ? 'No notes match that.' : 'The vault is empty. `jarvis mem add "..."`'));
		notes.sort((a, b) => String(b.updated).localeCompare(String(a.updated)));
		const w = Math.max(...notes.map((n) => n.folder.length));
		notes.forEach((n) => console.log(dim(n.folder.padEnd(w) + '  ') + bold(n.title) + (n.links.length ? dim('  → ' + n.links.join(', ')) : '')));
		console.log(dim('\n' + notes.length + ' note' + (notes.length === 1 ? '' : 's')));
		return;
	}
	if (sub === 'show') {
		const note = V.findNote(vault, rest.join(' '));
		if (!note) die('No note matches "' + rest.join(' ') + '".');
		const all = V.listNotes(vault);
		console.log('\n' + bold(note.title) + dim('  ' + note.folder + '/' + path.basename(note.file)));
		console.log('\n' + note.body + '\n');
		if (note.links.length) console.log(dim('Links out: ') + note.links.join(', '));
		const back = V.backlinks(all, note.title);
		if (back.length) console.log(dim('Links in:  ') + back.map((b) => b.title).join(', '));
		if (!note.links.length && !back.length) console.log(dim('No links yet — try `jarvis mem link "' + note.title + '" "Something Else"`'));
		console.log('');
		return;
	}
	if (sub === 'link') {
		const a = V.findNote(vault, rest[0]);
		if (!a) die('No note matches "' + rest[0] + '".');
		const bTitle = rest.slice(1).join(' ');
		if (!bTitle) die('Link it to what? `jarvis mem link <a> <b>`');
		const b = V.findLoose(vault, bTitle);   // title only — see findNote in vault.mjs
		V.addLink(vault, a, b ? b.title : bTitle);
		/* Linked both ways when both ends exist. A one-way link is a footnote;
		 * a two-way one is what makes the graph navigable from either side. */
		if (b) V.addLink(vault, V.readNote(b.file, vault), a.title);
		console.log(ok('✓') + ' ' + a.title + ' ↔ ' + (b ? b.title : bTitle + dim(' (not written yet)')));
		return;
	}
	if (sub === 'rm') {
		const note = V.findNote(vault, rest.join(' '));
		if (!note) die('No note matches "' + rest.join(' ') + '".');
		V.removeNote(note);
		console.log(ok('✓') + ' deleted ' + note.title);
		return;
	}
	if (sub === 'suggest') {
		const apply = hasFlag('apply');
		if (apply) {
			/* Recomputed each round rather than applied from one snapshot:
			 * linking A to B changes what is still worth suggesting, and a
			 * stale list would re-offer links that now exist. */
			let done = 0;
			for (let round = 0; round < 500; round++) {
				const next = V.suggestLinks(V.listNotes(vault))[0];
				if (!next) break;
				const a = V.findByTitle(vault, next.from);
				if (!a) break;
				V.addLink(vault, a, next.to);
				const b = V.findByTitle(vault, next.to);
				if (b) V.addLink(vault, V.readNote(b.file, vault), next.from);
				console.log(ok('✓') + ' ' + next.from + ' ↔ ' + next.to);
				done++;
			}
			console.log(dim('\n' + (done ? done + ' link' + (done === 1 ? '' : 's') + ' added.' : 'Nothing to add — every note that names another already points at it.')));
			return;
		}
		const list = V.suggestLinks(V.listNotes(vault));
		if (!list.length) return console.log(dim('Nothing to suggest — every note that names another already points at it.'));
		list.slice(0, 40).forEach((sug) => {
			console.log(bold(sug.from) + dim(' → ') + bold(sug.to));
			console.log(dim('   ' + sug.where));
		});
		if (list.length > 40) console.log(dim('\n…and ' + (list.length - 40) + ' more.'));
		console.log(dim('\n' + list.length + ' suggestion' + (list.length === 1 ? '' : 's') + ' · `jarvis mem suggest --apply` to add them all'));
		return;
	}
	if (sub === 'open') {
		const note = V.findNote(vault, rest.join(' '));
		if (!note) die('No note matches "' + rest.join(' ') + '".');
		const editor = process.env.EDITOR || process.env.VISUAL;
		if (editor) spawn(editor, [note.file], { stdio: 'inherit' });
		else if (!openExternally(note.file)) die('Set $EDITOR, or open ' + note.file + ' yourself.');
		return;
	}
	die('Unknown: jarvis mem ' + sub);
}

/* --------------------------------- graph --------------------------------- */

function cmdGraph(cfg, rest) {
	const vault = vaultOf(cfg);
	const open = hasFlag('open');
	const noFolders = hasFlag('no-folders');
	const depth = Number(flag('depth', 'd')) || 2;
	const notes = V.listNotes(vault);
	if (!notes.length) die('The vault is empty. `jarvis mem add "..."` first.');
	const title = rest.filter((a) => !a.startsWith('-')).join(' ').trim();

	if (open) {
		const graph = V.buildGraph(notes, { folders: !noFolders });
		const out = path.join(vault, '.jarvis', 'graph.html');
		fs.mkdirSync(path.dirname(out), { recursive: true });
		fs.writeFileSync(out, G.toHtml(graph, { title: path.basename(vault) }));
		console.log(ok('✓') + ' ' + out);
		openExternally(out) || console.log(dim('  Open it yourself — no handler for HTML files here.'));
		return;
	}
	if (title) {
		console.log('\n' + G.asciiTree(notes, V.findNote(vault, title)?.title || title, depth) + '\n');
		return;
	}
	const graph = V.buildGraph(notes, { folders: !noFolders });
	const counts = graph.nodes.reduce((a, n) => { a[n.kind] = (a[n.kind] || 0) + 1; return a; }, {});
	console.log('\n' + bold(path.basename(vault)) + '  ' + dim(vault));
	console.log('  ' + (counts.note || 0) + ' notes · ' + (counts.folder || 0) + ' folders · ' +
		(counts.unresolved || 0) + ' not yet written · ' + graph.edges.length + ' links\n');
	const hubs = graph.nodes.filter((n) => n.kind !== 'folder').sort((a, b) => b.deg - a.deg).slice(0, 10);
	if (hubs.length && hubs[0].deg) {
		console.log(dim('  Most connected'));
		hubs.filter((h) => h.deg).forEach((h) => console.log('  ' + String(h.deg).padStart(3) + '  ' + h.title + (h.kind === 'unresolved' ? dim('  (not written yet)') : '')));
	}
	const orphans = graph.nodes.filter((n) => n.kind === 'note' && n.deg <= 1).map((n) => n.title);
	if (orphans.length) console.log('\n' + dim('  Unlinked (' + orphans.length + '): ') + orphans.slice(0, 12).join(', ') + (orphans.length > 12 ? dim(' …') : ''));
	console.log('\n' + dim('  jarvis graph --open   for the picture'));
	console.log(dim('  jarvis graph <title>  for one note\'s neighbourhood\n'));
}

/* --------------------------------- chains -------------------------------- */

function chainsPath(vault) { return path.join(vault, '.jarvis', 'chains.json'); }
function readChains(vault) {
	try { return JSON.parse(fs.readFileSync(chainsPath(vault), 'utf8')); } catch { return []; }
}
function writeChains(vault, list) {
	fs.mkdirSync(path.dirname(chainsPath(vault)), { recursive: true });
	fs.writeFileSync(chainsPath(vault), JSON.stringify(list, null, 2) + '\n');
}

async function cmdChain(cfg, sub, rest) {
	const vault = vaultOf(cfg);
	const chains = readChains(vault);
	if (sub === 'list' || !sub) {
		if (!chains.length) return console.log(dim('No chains. `jarvis chain add "Morning" "note: Today" "prompt: what is on my calendar"`'));
		chains.forEach((ch) => {
			console.log(bold(ch.name) + dim('  ' + ch.steps.length + ' step' + (ch.steps.length === 1 ? '' : 's')));
			ch.steps.forEach((s, i) => console.log(dim('  ' + (i + 1) + '. ' + s.kind + ': ') + (s.kind === 'note' ? s.title : s.text)));
		});
		return;
	}
	if (sub === 'add') {
		const name = rest[0];
		if (!name) die('Name it: `jarvis chain add "Morning" "prompt: ..."`');
		const steps = rest.slice(1).map((raw) => {
			const m = raw.match(/^(note|prompt)\s*:\s*(.*)$/i);
			if (!m) return { kind: 'prompt', text: raw };
			return m[1].toLowerCase() === 'note' ? { kind: 'note', title: m[2].trim() } : { kind: 'prompt', text: m[2].trim() };
		});
		if (!steps.length) die('A chain needs at least one step.');
		const i = chains.findIndex((ch) => ch.name.toLowerCase() === name.toLowerCase());
		const rec = { name, steps };
		if (i < 0) chains.push(rec); else chains[i] = rec;
		writeChains(vault, chains);
		console.log(ok('✓') + ' ' + name + dim(' · ' + steps.length + ' steps'));
		return;
	}
	if (sub === 'rm') {
		const name = rest.join(' ').toLowerCase();
		writeChains(vault, chains.filter((ch) => ch.name.toLowerCase() !== name));
		console.log(ok('✓') + ' removed ' + name);
		return;
	}
	if (sub === 'run') {
		const q = rest.join(' ').toLowerCase();
		const chain = chains.find((ch) => ch.name.toLowerCase() === q) || chains.find((ch) => ch.name.toLowerCase().includes(q));
		if (!chain) die('No chain called "' + rest.join(' ') + '". Saved: ' + (chains.map((ch) => ch.name).join(', ') || 'none'));
		console.log(dim('running ') + bold(chain.name) + '\n');
		const carried = [];
		for (const [i, step] of chain.steps.entries()) {
			if (step.kind === 'note') {
				const n = V.findNote(vault, step.title);
				if (!n) { console.log(bad('✗') + ' step ' + (i + 1) + ': no note "' + step.title + '"'); return; }
				carried.push('# ' + n.title + '\n' + n.body);
				console.log(ok('✓') + ' ' + dim('step ' + (i + 1) + ' · read ') + n.title);
				continue;
			}
			console.log(dim('· step ' + (i + 1) + ' · ') + step.text);
			await turn(cfg, step.text, { extraContext: carried.join('\n\n') });
			carried.length = 0;
			console.log('');
		}
		return;
	}
	die('Unknown: jarvis chain ' + sub);
}

/* --------------------------------- misc ---------------------------------- */

function cmdUsage(cfg) {
	const vault = vaultOf(cfg);
	const u = P.readUsage(vault);
	console.log('\n' + bold('Tokens and cost') + dim('  since ' + new Date(u.since).toLocaleDateString()));
	console.log('  ' + u.calls + ' calls · ' + fmtTokens(u.in) + ' in · ' + fmtTokens(u.out) + ' out · ' + bold(fmtCost(u.cost)));
	const rows = Object.entries(u.models).sort((a, b) => (b[1].in + b[1].out) - (a[1].in + a[1].out));
	if (rows.length) {
		console.log('');
		rows.forEach(([name, m]) => console.log('  ' + name.padEnd(24) + dim(m.calls + ' calls  ') +
			fmtTokens(m.in) + ' in  ' + fmtTokens(m.out) + ' out  ' + (P.priceFor(name) ? fmtCost(m.cost) : dim('price unknown'))));
	}
	console.log(dim('\n  Counted from what each provider reported, not estimated.\n'));
}

function cmdConfig(cfg, rest) {
	if (!rest.length) {
		console.log('\n' + dim(CONFIG_PATH) + '\n');
		Object.keys(cfg).sort().forEach((k) => {
			console.log('  ' + k.padEnd(16) + (SECRET_KEYS.includes(k) ? dim(redact(cfg[k])) : String(cfg[k])));
		});
		console.log('');
		return;
	}
	const [k, ...v] = rest;
	if (!v.length) return console.log(SECRET_KEYS.includes(k) ? redact(cfg[k]) : String(cfg[k] ?? '(not set)'));
	cfg[k] = v.join(' ');
	saveConfig(cfg);
	console.log(ok('✓') + ' ' + k + ' = ' + (SECRET_KEYS.includes(k) ? redact(cfg[k]) : cfg[k]));
}

/* The bridge to the web app. Neither side can reach the other's storage — a
 * browser cannot read your disk unprompted and this cannot read localStorage —
 * so the honest answer is a file you move across, not a claim of sync. */
function cmdExport(cfg, rest) {
	const vault = vaultOf(cfg);
	const notes = V.listNotes(vault);
	const out = rest[0] || path.join(process.cwd(), 'jarvis-vault-export.json');
	const payload = {
		app: 'jarvis', version: 1, exportedAt: new Date().toISOString(), includesKeys: false,
		data: {
			vault: notes.map((n) => ({ id: n.title.toLowerCase(), title: n.title, folder: n.folder, body: n.body, at: Date.parse(n.updated) || Date.now() })),
			chains: readChains(vault).map((ch) => ({
				id: ch.name.toLowerCase().replace(/\s+/g, '-'), name: ch.name,
				steps: ch.steps.map((s) => (s.kind === 'note' ? { kind: 'say', text: 'Read the note "' + s.title + '" and use it.' } : { kind: 'say', text: s.text })),
			})),
			usage: P.readUsage(vault),
		},
	};
	fs.writeFileSync(out, JSON.stringify(payload, null, 2) + '\n');
	console.log(ok('✓') + ' ' + out + dim('  · ' + notes.length + ' notes'));
	console.log(dim('  Import it in the app: Settings → Data → Import.'));
}

function cmdImport(cfg, rest) {
	const file = rest[0];
	if (!file) die('Which file? `jarvis import jarvis-backup.json`');
	const vault = V.ensureVault(cfg.vault);
	let payload;
	try { payload = JSON.parse(fs.readFileSync(file, 'utf8')); } catch (e) { die('Could not read that file: ' + e.message); }
	const data = payload.data || payload;
	let n = 0;
	(data.vault || []).forEach((note) => {
		V.writeNote(vault, { title: note.title, folder: note.folder || V.DEFAULT_FOLDER, body: note.body });
		n++;
	});
	/* A pre-vault backup carries memory as bare strings. Each becomes a note so
	 * nothing is dropped on the way in. */
	(data.memory || []).forEach((fact) => {
		if (typeof fact !== 'string') return;
		V.writeNote(vault, { title: V.titleFrom(fact), folder: 'Memory', body: fact });
		n++;
	});
	if (Array.isArray(data.chains) && data.chains.length) {
		writeChains(vault, data.chains.map((ch) => ({
			name: ch.name,
			steps: (ch.steps || []).map((s) => (s.kind === 'say' ? { kind: 'prompt', text: s.text } : { kind: 'prompt', text: 'Run the ' + s.tool + ' tool with ' + JSON.stringify(s.args || {}) })),
		})));
	}
	console.log(ok('✓') + ' imported ' + n + ' note' + (n === 1 ? '' : 's') + ' into ' + vault);
}

/* --------------------------------- main ---------------------------------- */

async function main() {
	const cfg = loadConfig();
	if (!args.length || args[0] === 'help' || args[0] === '--help' || args[0] === '-h') { console.log(HELP); return; }
	if (args[0] === '--version' || args[0] === '-v') { console.log('jarvis 1.0.0'); return; }

	const cmd = args[0];
	if (cmd === 'login') return cmdLogin(cfg);
	if (cmd === 'logout') return cmdLogout(cfg);
	if (cmd === 'init') return cmdInit(cfg);
	if (cmd === 'mem' || cmd === 'memory') { args.shift(); const sub = args.shift(); return cmdMem(cfg, sub, args); }
	if (cmd === 'graph') { args.shift(); return cmdGraph(cfg, args); }
	if (cmd === 'chain' || cmd === 'chains') { args.shift(); const sub = args.shift(); return cmdChain(cfg, sub, args); }
	if (cmd === 'usage') return cmdUsage(cfg);
	if (cmd === 'config') { args.shift(); return cmdConfig(cfg, args); }
	if (cmd === 'export') { args.shift(); return cmdExport(cfg, args); }
	if (cmd === 'import') { args.shift(); return cmdImport(cfg, args); }

	/* Anything that is not a subcommand is treated as the question, so
	 * `jarvis "what's on my plate"` works without typing `ask`. */
	if (cmd === 'ask') args.shift();
	const model = flag('model', 'm');
	const noMemory = hasFlag('no-memory');
	const question = args.filter((a) => !a.startsWith('-')).join(' ').trim();
	if (!question) { console.log(HELP); return; }
	await turn(cfg, question, { model: model === true ? null : model, noMemory });
}

main().catch((err) => die(err && err.stack ? err.stack : String(err)));
