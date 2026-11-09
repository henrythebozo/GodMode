/**
 * Everything the World page keeps in localStorage.
 *
 * The sign-in session and the Anthropic key belong to Henry OS (index.html
 * writes them, under the names below) and are only read here. The page's own
 * settings and the last finished mission live under `henryos.world.*`.
 * Storage can be unavailable or full, so every access is guarded.
 */
import { DEFAULT_MODEL, modelById } from './models.js';

const read = (key) => {
	try {
		return localStorage.getItem(key);
	} catch {
		return null;
	}
};

const write = (key, value) => {
	try {
		if (value === null) localStorage.removeItem(key);
		else localStorage.setItem(key, value);
		return true;
	} catch {
		return false;
	}
};

const readJson = (key) => {
	try {
		return JSON.parse(read(key));
	} catch {
		return null;
	}
};

export const store = {
	get signedIn() {
		return Boolean(readJson('henryos.session'));
	},
	get anthropicKey() {
		return read('godmode.key.anthropic') || '';
	},
	/** Henry OS's own "Enter sends" setting, so the composer here behaves the same. */
	get enterSends() {
		return read('godmode.enter') !== '0';
	},
	get model() {
		return modelById(read('henryos.world.model') || DEFAULT_MODEL).id;
	},
	set model(id) {
		write('henryos.world.model', modelById(id).id);
	},
	get webSearch() {
		return read('henryos.world.search') !== '0';
	},
	set webSearch(on) {
		write('henryos.world.search', on ? '1' : '0');
	},
	/** The last finished mission, so a reload (or a phone dropping the tab) keeps it. */
	get lastMission() {
		return readJson('henryos.world.last');
	},
	set lastMission(snapshot) {
		write('henryos.world.last', snapshot ? JSON.stringify(snapshot) : null);
	},
};
