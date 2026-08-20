/* `jarvis login` — sign in instead of pasting a key.
 *
 * OpenRouter is the only one of the four providers where this is possible
 * without registering an application: its OAuth uses PKCE and needs no client
 * id and no client secret. Anthropic's OAuth is reserved for Anthropic's own
 * clients, and Google's needs a Cloud project, a consent screen and a
 * client_secret.json — more setup than the API key it replaces. Since
 * OpenRouter brokers Claude, Gemini and GPT, one sign-in reaches all three.
 *
 * The loopback pattern is the standard one for a command-line client: bind a
 * server to 127.0.0.1 on a port the OS picks, send the browser to the
 * authorize endpoint with that address as the callback, and read the code out
 * of the request that comes back. Nothing is exposed beyond the loopback
 * interface and the server lives only for the length of the sign-in.
 */
import http from 'node:http';
import crypto from 'node:crypto';
import { spawn } from 'node:child_process';

export const OR_AUTH_URL = 'https://openrouter.ai/auth';
export const OR_KEYS_URL = 'https://openrouter.ai/api/v1/auth/keys';

const b64url = (buf) => Buffer.from(buf).toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');

export function makeVerifier() {
	return b64url(crypto.randomBytes(32));
}
export function challengeFor(verifier) {
	return b64url(crypto.createHash('sha256').update(verifier).digest());
}
export function authUrl(callback, challenge) {
	return OR_AUTH_URL +
		'?callback_url=' + encodeURIComponent(callback) +
		'&code_challenge=' + encodeURIComponent(challenge) +
		'&code_challenge_method=S256';
}

export async function exchangeCode(code, verifier, fetchImpl) {
	const f = fetchImpl || fetch;
	const res = await f(OR_KEYS_URL, {
		method: 'POST',
		headers: { 'Content-Type': 'application/json' },
		body: JSON.stringify({ code, code_verifier: verifier, code_challenge_method: 'S256' }),
	});
	if (!res.ok) {
		let detail = res.status + ' ' + res.statusText;
		try { detail = (await res.json()).error?.message || detail; } catch {}
		throw new Error(detail);
	}
	const data = await res.json();
	if (!data || !data.key) throw new Error('OpenRouter did not return a key.');
	return data.key;
}

const PAGE = (title, body) => `<!doctype html><meta charset="utf-8"><title>${title}</title>
<style>
	:root { color-scheme: dark light; }
	body { background:#262624; color:#faf9f7; font:15px/1.6 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif;
	       display:grid; place-items:center; height:100vh; margin:0; text-align:center; padding:24px; }
	b { display:block; font-size:19px; margin-bottom:8px; }
	p { color:rgba(255,255,255,.62); max-width:34rem; margin:0; }
	@media (prefers-color-scheme: light) { body { background:#faf9f7; color:#1f1e1d; } p { color:rgba(63,60,56,.76); } }
</style>
<div><b>${title}</b><p>${body}</p></div>`;

/* Resolves with the code, or rejects on timeout or a refusal from OpenRouter.
 * The response is written before resolving so the browser has something to
 * show — closing the socket first leaves the tab on an error page even when
 * the sign-in worked. */
export function waitForCode(opts) {
	opts = opts || {};
	const timeoutMs = opts.timeoutMs || 180000;
	return new Promise((resolve, reject) => {
		let done = false;
		const server = http.createServer((req, res) => {
			const url = new URL(req.url, 'http://127.0.0.1');
			if (url.pathname === '/favicon.ico') { res.writeHead(204); res.end(); return; }
			const code = url.searchParams.get('code');
			const error = url.searchParams.get('error');
			const finish = (title, body, fn) => {
				res.writeHead(code ? 200 : 400, { 'Content-Type': 'text/html; charset=utf-8' });
				res.end(PAGE(title, body));
				if (done) return;
				done = true;
				clearTimeout(timer);
				server.close(() => fn());
			};
			if (code) finish('Signed in.', 'You can close this tab and go back to the terminal.', () => resolve(code));
			else if (error) finish('Sign-in refused.', 'OpenRouter said: ' + error, () => reject(new Error(error)));
			else { res.writeHead(404); res.end(); }
		});
		const timer = setTimeout(() => {
			if (done) return;
			done = true;
			server.close(() => reject(new Error('Timed out waiting for the browser. Run `jarvis login --manual` if this machine has no browser.')));
		}, timeoutMs);
		server.on('error', (err) => { if (!done) { done = true; clearTimeout(timer); reject(err); } });
		/* Loopback only, and never a fixed port — a hardcoded one collides with
		 * whatever else is running and hands any other local process a target. */
		server.listen(opts.port || 0, '127.0.0.1', () => {
			const { port } = server.address();
			try { opts.onReady && opts.onReady(port, 'http://127.0.0.1:' + port + '/callback'); }
			catch (err) { if (!done) { done = true; clearTimeout(timer); server.close(() => reject(err)); } }
		});
	});
}

export function openBrowser(url) {
	const cmd = process.platform === 'darwin' ? 'open' : process.platform === 'win32' ? 'start' : 'xdg-open';
	try {
		const p = spawn(cmd, [url], { stdio: 'ignore', detached: true, shell: process.platform === 'win32' });
		p.on('error', () => {});
		p.unref();
		return true;
	} catch { return false; }
}
