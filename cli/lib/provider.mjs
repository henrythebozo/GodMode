/* The same four providers the web app talks to, in the same shapes, with the
 * same usage accounting — deliberately a port rather than a shared module,
 * because docs/jarvis.html is a single no-build file with no imports and a
 * shared module would break that. When one side changes, change both; the
 * request bodies and the SSE parsing are the parts that must stay in step.
 */
import fs from 'node:fs';
import path from 'node:path';

const OPENROUTER_BASE = 'https://openrouter.ai/api/v1';

/* A bare model id (no `gpt:` / `claude:` / `gemini:` prefix) goes to an
 * OpenAI-compatible endpoint, OpenRouter by default. baseUrl redirects that at
 * anything else speaking the same protocol — Ollama, llama.cpp, LM Studio, a
 * company gateway — which is the one thing a terminal tool really ought to
 * support and costs nothing to allow. No key is demanded when it is not the
 * hosted default, because a local server usually has none. */
export function backendFor(modelId, cfg) {
	const m = String(modelId || '').match(/^(gpt|claude|gemini):(.*)$/);
	if (!m) {
		const base = String(cfg.baseUrl || OPENROUTER_BASE).replace(/\/+$/, '');
		const hosted = base === OPENROUTER_BASE;
		if (hosted && !cfg.key) throw new Error('No OpenRouter key. Run `jarvis init`, or set OPENROUTER_API_KEY.');
		const headers = { 'Content-Type': 'application/json', 'X-Title': 'Jarvis CLI' };
		if (cfg.key) headers.Authorization = 'Bearer ' + cfg.key;
		return { kind: 'openai', model: modelId, url: base + '/chat/completions', headers };
	}
	const [, vendor, model] = m;
	if (vendor === 'gpt') {
		if (!cfg.oaiKey) throw new Error('No OpenAI key. Run `jarvis init`, or set OPENAI_API_KEY.');
		return { kind: 'openai', model, url: 'https://api.openai.com/v1/chat/completions', headers: { Authorization: 'Bearer ' + cfg.oaiKey, 'Content-Type': 'application/json' } };
	}
	if (vendor === 'gemini') {
		if (!cfg.geminiKey) throw new Error('No Gemini key. Run `jarvis init`, or set GEMINI_API_KEY.');
		return { kind: 'gemini', model, url: 'https://generativelanguage.googleapis.com/v1beta/models/' + model + ':streamGenerateContent?alt=sse', headers: { 'x-goog-api-key': cfg.geminiKey, 'Content-Type': 'application/json' } };
	}
	if (!cfg.anthKey) throw new Error('No Anthropic key. Run `jarvis init`, or set ANTHROPIC_API_KEY.');
	return {
		kind: 'anthropic', model, url: 'https://api.anthropic.com/v1/messages',
		headers: { 'x-api-key': cfg.anthKey, 'anthropic-version': '2023-06-01', 'Content-Type': 'application/json' },
	};
}

/* Returns { text, usage } for one SSE event. Anthropic reports input on
 * message_start and output on message_delta; Gemini repeats a cumulative
 * usageMetadata; OpenAI-shaped endpoints send one usage object on a final
 * chunk that only appears if stream_options asked for it. */
export function parseEvent(kind, data) {
	const ev = JSON.parse(data);
	if (kind === 'anthropic') {
		const out = { text: undefined, usage: null };
		if (ev.type === 'content_block_delta') out.text = ev.delta?.text;
		if (ev.type === 'message_start' && ev.message?.usage) out.usage = { in: ev.message.usage.input_tokens || 0 };
		if (ev.type === 'message_delta' && ev.usage) out.usage = { out: ev.usage.output_tokens || 0 };
		return out;
	}
	if (kind === 'gemini') {
		const parts = ev.candidates?.[0]?.content?.parts;
		const u = ev.usageMetadata;
		return {
			text: Array.isArray(parts) ? parts.map((p) => p.text || '').join('') : undefined,
			usage: u ? { in: u.promptTokenCount || 0, out: u.candidatesTokenCount || 0 } : null,
		};
	}
	return {
		text: ev.choices?.[0]?.delta?.content,
		usage: ev.usage ? { in: ev.usage.prompt_tokens || 0, out: ev.usage.completion_tokens || 0 } : null,
	};
}

const noStreamOptions = new Set();

export async function stream(modelId, messages, cfg, onDelta, signal) {
	const backend = backendFor(modelId, cfg);
	let body;
	if (backend.kind === 'gemini') {
		const sys = messages.find((m) => m.role === 'system');
		body = { contents: messages.filter((m) => m.role !== 'system').map((m) => ({ role: m.role === 'assistant' ? 'model' : 'user', parts: [{ text: m.content }] })) };
		if (sys) body.systemInstruction = { parts: [{ text: sys.content }] };
	} else if (backend.kind === 'anthropic') {
		const sys = messages.find((m) => m.role === 'system');
		body = {
			model: backend.model, max_tokens: 2048, stream: true,
			messages: messages.filter((m) => m.role !== 'system').map((m) => ({ role: m.role === 'assistant' ? 'assistant' : 'user', content: m.content })),
		};
		if (sys) body.system = sys.content;
	} else {
		body = { model: backend.model, messages, stream: true };
		if (!noStreamOptions.has(backend.url)) body.stream_options = { include_usage: true };
	}

	const res = await fetch(backend.url, { method: 'POST', headers: backend.headers, body: JSON.stringify(body), signal });
	if (!res.ok) {
		let detail = res.status + ' ' + res.statusText;
		try { detail = (await res.json()).error?.message || detail; } catch {}
		/* Some OpenAI-compatible endpoints 400 on unknown parameters rather than
		 * ignoring them. Losing a token count is a far better failure than
		 * losing the request, so it drops the parameter and retries once. */
		if (res.status === 400 && body.stream_options && /stream_options/i.test(detail)) {
			noStreamOptions.add(backend.url);
			return stream(modelId, messages, cfg, onDelta, signal);
		}
		throw new Error(detail);
	}

	const reader = res.body.getReader();
	const decoder = new TextDecoder();
	const used = { in: 0, out: 0 };
	let buf = '', text = '';
	try {
		for (;;) {
			const { done, value } = await reader.read();
			if (done) break;
			buf += decoder.decode(value, { stream: true });
			const lines = buf.split('\n');
			buf = lines.pop();
			for (const line of lines) {
				const data = line.startsWith('data: ') ? line.slice(6).trim() : null;
				if (!data || data === '[DONE]') continue;
				try {
					const ev = parseEvent(backend.kind, data);
					if (ev.usage) {
						if (ev.usage.in) used.in = ev.usage.in;
						if (ev.usage.out) used.out = ev.usage.out;
					}
					if (ev.text) { text += ev.text; if (onDelta) onDelta(ev.text); }
				} catch {}
			}
		}
	} finally {
		try { const c = reader.cancel(); if (c && c.catch) c.catch(() => {}); } catch {}
	}
	return { text, usage: used, model: modelId };
}

/* Public list rates, USD per million tokens. A model that is not here reports
 * tokens and no cost — a confidently wrong figure about someone's money is
 * worse than a blank. Kept identical to the table in docs/jarvis.html. */
const MODEL_PRICES = [
	[/claude-opus-4|claude-opus-5/i, 15, 75],
	[/claude-sonnet-4|claude-sonnet-5/i, 3, 15],
	[/claude-3-5-haiku|claude-haiku-4/i, 0.8, 4],
	[/claude-3-opus/i, 15, 75],
	[/claude-3-5-sonnet|claude-3-7-sonnet/i, 3, 15],
	[/gpt-4o-mini/i, 0.15, 0.6],
	[/gpt-4o/i, 2.5, 10],
	[/gpt-4\.1-mini/i, 0.4, 1.6],
	[/gpt-4\.1/i, 2, 8],
	[/o3-mini/i, 1.1, 4.4],
	[/gpt-5-mini/i, 0.25, 2],
	[/gpt-5/i, 1.25, 10],
	[/gemini-2\.5-pro|gemini-1\.5-pro/i, 1.25, 10],
	[/gemini-2\.5-flash|gemini-2\.0-flash|gemini-1\.5-flash/i, 0.3, 2.5],
];
export function priceFor(modelId) {
	for (const [re, i, o] of MODEL_PRICES) if (re.test(String(modelId || ''))) return { in: i, out: o };
	return null;
}
export function costOf(modelId, inTok, outTok) {
	const p = priceFor(modelId);
	return p ? (inTok / 1e6) * p.in + (outTok / 1e6) * p.out : null;
}

export function usagePath(vault) { return path.join(vault, '.jarvis', 'usage.json'); }
export function readUsage(vault) {
	try { return JSON.parse(fs.readFileSync(usagePath(vault), 'utf8')); }
	catch { return { calls: 0, in: 0, out: 0, cost: 0, since: Date.now(), models: {} }; }
}
export function recordUsage(vault, modelId, inTok, outTok) {
	if (!inTok && !outTok) return null;
	const u = readUsage(vault);
	u.calls += 1; u.in += inTok; u.out += outTok;
	const c = costOf(modelId, inTok, outTok);
	if (c !== null) u.cost += c;
	const k = String(modelId).includes(':') ? String(modelId).split(':')[1] : String(modelId);
	const m = u.models[k] || { calls: 0, in: 0, out: 0, cost: 0 };
	m.calls += 1; m.in += inTok; m.out += outTok;
	if (c !== null) m.cost += c;
	u.models[k] = m;
	fs.mkdirSync(path.dirname(usagePath(vault)), { recursive: true });
	fs.writeFileSync(usagePath(vault), JSON.stringify(u, null, 2) + '\n');
	return { in: inTok, out: outTok, cost: c };
}
