/* Config and paths.
 *
 * Keys live in ~/.jarvis/config.json with 0600 permissions, NOT in the vault.
 * The vault is the thing you are meant to sync, open in Obsidian and put in a
 * git repo; a credential that rides along with it will eventually be pushed
 * somewhere public. Environment variables win over the file so CI and
 * throwaway shells never have to write one.
 */
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';

export const HOME = process.env.JARVIS_HOME || path.join(os.homedir(), '.jarvis');
export const CONFIG_PATH = path.join(HOME, 'config.json');

const DEFAULTS = {
	vault: path.join(os.homedir(), 'jarvis-vault'),
	model: 'claude:claude-sonnet-5',
	assistantName: 'Jarvis',
	userName: '',
	maxContextNotes: 12,
};

/* env name -> config key, in the order backendFor() checks them */
const ENV_KEYS = {
	JARVIS_OPENROUTER_KEY: 'key',
	OPENROUTER_API_KEY: 'key',
	JARVIS_OPENAI_KEY: 'oaiKey',
	OPENAI_API_KEY: 'oaiKey',
	JARVIS_ANTHROPIC_KEY: 'anthKey',
	ANTHROPIC_API_KEY: 'anthKey',
	JARVIS_GEMINI_KEY: 'geminiKey',
	GEMINI_API_KEY: 'geminiKey',
};

export function loadConfig() {
	let file = {};
	try { file = JSON.parse(fs.readFileSync(CONFIG_PATH, 'utf8')); } catch {}
	const cfg = { ...DEFAULTS, ...file };
	for (const [env, key] of Object.entries(ENV_KEYS)) {
		if (process.env[env] && !cfg[key]) cfg[key] = process.env[env];
	}
	if (process.env.JARVIS_VAULT) cfg.vault = process.env.JARVIS_VAULT;
	if (process.env.JARVIS_MODEL) cfg.model = process.env.JARVIS_MODEL;
	if (process.env.JARVIS_BASE_URL) cfg.baseUrl = process.env.JARVIS_BASE_URL;
	return cfg;
}

/* `persistEnvKeys` is the deliberate opt-out from the rule below, and the only
 * caller is `jarvis key import` — where writing an environment key to disk is
 * the entire point of the command and the person typing it said so out loud. */
export function saveConfig(cfg, opts) {
	const keep = new Set((opts && opts.persistEnvKeys) || []);
	fs.mkdirSync(HOME, { recursive: true, mode: 0o700 });
	const onDisk = { ...cfg };
	/* A key that only ever came from the environment is not written back —
	 * saving it would silently turn a per-shell secret into a stored one. */
	for (const [env, key] of Object.entries(ENV_KEYS)) {
		if (keep.has(key)) continue;
		if (process.env[env] && onDisk[key] === process.env[env]) delete onDisk[key];
	}
	fs.writeFileSync(CONFIG_PATH, JSON.stringify(onDisk, null, 2) + '\n', { mode: 0o600 });
	try { fs.chmodSync(CONFIG_PATH, 0o600); } catch {}
	return CONFIG_PATH;
}

/* What is in the environment right now, whether or not the config file already
 * has something for the same provider. `jarvis key import` needs the raw view:
 * loadConfig() hides an environment key behind a stored one, and a command
 * whose job is "show me what this machine already has" must not inherit that. */
export function envKeys() {
	const found = [];
	for (const [env, field] of Object.entries(ENV_KEYS)) {
		const value = process.env[env];
		if (value && !found.some((f) => f.field === field)) found.push({ env, field, value });
	}
	return found;
}

/* Where each key actually came from, which is the question anyone debugging
 * "why is it still using the old key" is really asking. */
export function keyOrigins(cfg) {
	let file = {};
	try { file = JSON.parse(fs.readFileSync(CONFIG_PATH, 'utf8')); } catch {}
	return SECRET_KEYS.map((field) => {
		const env = Object.entries(ENV_KEYS).find(([e, f]) => f === field && process.env[e] && process.env[e] === cfg[field]);
		const value = cfg[field] || '';
		let origin = 'not set';
		if (value && env) origin = '$' + env[0];
		else if (value && file[field] === value) origin = CONFIG_PATH;
		else if (value) origin = 'set';
		return { field, value, origin, alsoOnDisk: !!file[field] };
	});
}

/* The same four shapes the web app matches a pasted key against — see the
 * paste-detection block in docs/jarvis.html. Deliberate duplicate: the page
 * has no imports, so a shared module is not available to it. Change both.
 * Order matters — sk-ant- and sk-or- are also "sk-". */
export const KEY_SHAPES = [
	{ field: 'anthKey', label: 'Anthropic', model: 'claude:claude-sonnet-5', re: /^sk-ant-[A-Za-z0-9\-_]{16,}$/ },
	{ field: 'key', label: 'OpenRouter', model: 'anthropic/claude-sonnet-5', re: /^sk-or-[A-Za-z0-9\-_]{16,}$/ },
	{ field: 'oaiKey', label: 'OpenAI', model: 'gpt:gpt-4o', re: /^sk-[A-Za-z0-9\-_]{16,}$/ },
	{ field: 'geminiKey', label: 'Gemini', model: 'gemini:gemini-2.5-flash', re: /^AIza[A-Za-z0-9\-_]{30,}$/ },
];
export function identifyKey(text) {
	const t = String(text || '').trim();
	if (!t || /\s/.test(t) || t.length > 400) return null;   // a key is one token, never a sentence
	for (const shape of KEY_SHAPES) if (shape.re.test(t)) return { ...shape, value: t };
	return null;
}
/* "an Anthropic key" but "a Gemini key" — three of the four start with a
 * vowel, which is exactly how a hardcoded "an" survives review. */
export function keyArticle(label) { return /^[AEIOU]/.test(label) ? 'an' : 'a'; }
export function labelFor(field) {
	const s = KEY_SHAPES.find((k) => k.field === field);
	return s ? s.label : field;
}

export const SECRET_KEYS = ['key', 'oaiKey', 'anthKey', 'geminiKey'];
export function redact(v) {
	if (!v) return '(not set)';
	return v.length <= 10 ? '••••' : v.slice(0, 6) + '…' + v.slice(-4);
}
