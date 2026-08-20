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

export function saveConfig(cfg) {
	fs.mkdirSync(HOME, { recursive: true, mode: 0o700 });
	const onDisk = { ...cfg };
	/* A key that only ever came from the environment is not written back —
	 * saving it would silently turn a per-shell secret into a stored one. */
	for (const [env, key] of Object.entries(ENV_KEYS)) {
		if (process.env[env] && onDisk[key] === process.env[env]) delete onDisk[key];
	}
	fs.writeFileSync(CONFIG_PATH, JSON.stringify(onDisk, null, 2) + '\n', { mode: 0o600 });
	try { fs.chmodSync(CONFIG_PATH, 0o600); } catch {}
	return CONFIG_PATH;
}

export const SECRET_KEYS = ['key', 'oaiKey', 'anthKey', 'geminiKey'];
export function redact(v) {
	if (!v) return '(not set)';
	return v.length <= 10 ? '••••' : v.slice(0, 6) + '…' + v.slice(-4);
}
