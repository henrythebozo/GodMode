/**
 * Runs one agent: a single streamed request to Claude, reported as events.
 *
 * The client is passed in (the page hands over the Anthropic SDK client, the
 * tests a fake), so nothing here touches the network or the DOM directly.
 *
 * Events sent to `emit`:
 *   { type: 'thinking', delta }      summarized reasoning, as it streams
 *   { type: 'text', delta }          the answer, as it streams
 *   { type: 'tool', name, query }    a web search the model ran
 *   { type: 'note', text }           something the person should know
 */
import { addUsage, supportsFallback } from './models.js';

const FALLBACK_BETA = 'server-side-fallback-2026-07-01';

// One request plus up to four resumes of a paused server-tool turn.
const MAX_TURNS = 5;

/** `kind` is one of: aborted, auth, refusal, empty, api. */
export class AgentError extends Error {
	constructor(kind, message, cause) {
		super(message);
		this.name = 'AgentError';
		this.kind = kind;
		if (cause) this.cause = cause;
	}
}

/**
 * The assistant content to send back when resuming a paused turn.
 *
 * Normally that is the content unchanged. If the server switched to a
 * fallback model part-way, the API only accepts text and completed
 * server-tool calls from before the switch; reasoning and unfinished tool
 * calls from the declined model have to be left out, with the `fallback`
 * block kept where it was.
 */
export function echoContent(content) {
	const boundary = content.map((b) => b.type).lastIndexOf('fallback');
	if (boundary === -1) return content;
	const answered = new Set(content.map((b) => b.tool_use_id).filter(Boolean));
	return content.filter((block, i) => {
		if (i >= boundary) return true;
		if (block.type === 'text' || block.type === 'fallback') return true;
		if (block.type === 'server_tool_use') return answered.has(block.id);
		return Boolean(block.tool_use_id);
	});
}

function apiDetail(err) {
	return err?.error?.error?.message || err?.message || 'Unknown error';
}

function toAgentError(err, model) {
	const status = err?.status;
	if (status === 401) {
		return new AgentError('auth', 'Anthropic rejected the API key. Check it in Henry OS settings.', err);
	}
	if (status === 403) {
		return new AgentError('auth', `This API key is not allowed to do that: ${apiDetail(err)} Check it in Henry OS settings.`, err);
	}
	if (status === 404) {
		return new AgentError('api', `Anthropic does not recognise the model "${model}".`, err);
	}
	if (status === 429) {
		return new AgentError('api', 'Anthropic rate limit reached. Wait a minute, then run the mission again.', err);
	}
	if (status >= 500) {
		return new AgentError('api', 'Anthropic is overloaded right now. Try again shortly.', err);
	}
	if (status) return new AgentError('api', apiDetail(err), err);
	return new AgentError('api', 'Could not reach Anthropic. Check your connection.', err);
}

function refusalMessage(details) {
	const about = details?.category ? ` (${details.category})` : '';
	return `Claude declined this request${about}.`;
}

/**
 * @returns {Promise<{ text: string, sources: {url: string, title: string}[],
 *   truncated: boolean, usage: {input: number, output: number, searches: number},
 *   servedBy: string, note: string }>}
 * @throws {AgentError}
 */
export async function runAgent({
	client,
	model,
	system,
	user,
	effort = 'medium',
	maxTokens = 16000,
	schema = null,
	tools = null,
	signal,
	emit = () => {},
}) {
	const messages = [{ role: 'user', content: user }];
	const sources = new Map();
	let activeTools = tools?.length ? tools : null;
	let usage = addUsage();
	let servedBy = model;
	let text = '';
	let note = '';
	let truncated = false;
	let turns = 0;

	const send = () => {
		const params = {
			model,
			max_tokens: maxTokens,
			system,
			messages,
			// without `display` the reasoning comes back empty on current models
			thinking: { type: 'adaptive', display: 'summarized' },
			output_config: { effort },
		};
		if (schema) params.output_config.format = { type: 'json_schema', schema };
		if (activeTools) params.tools = activeTools;
		if (supportsFallback(model)) {
			// a classifier decline is retried on another model inside the same call
			params.betas = [FALLBACK_BETA];
			params.fallbacks = 'default';
		}
		const stream = client.beta.messages.stream(params, { signal });
		stream.on('thinking', (delta) => emit({ type: 'thinking', delta }));
		stream.on('text', (delta) => emit({ type: 'text', delta }));
		stream.on('contentBlock', (block) => {
			if (block.type === 'server_tool_use') {
				emit({ type: 'tool', name: block.name, query: block.input?.query || '' });
			} else if (block.type === 'fallback') {
				emit({
					type: 'note',
					text: `${block.from?.model || 'The model'} declined this step, so ${block.to?.model || 'another model'} answered it.`,
				});
			}
		});
		return stream.finalMessage();
	};

	for (;;) {
		let message;
		try {
			message = await send();
		} catch (err) {
			if (signal?.aborted) throw new AgentError('aborted', 'Stopped.', err);
			if (err?.status === 400 && activeTools && turns === 0) {
				// most likely web search is not enabled for this API key's organisation
				activeTools = null;
				note = 'Web search was not available, so this was written without it.';
				emit({ type: 'note', text: note });
				continue;
			}
			throw toAgentError(err, model);
		}
		turns++;
		usage = addUsage(usage, message.usage);
		servedBy = message.model || servedBy;

		// a refusal is a normal 200 response: check before reading any content
		if (message.stop_reason === 'refusal') {
			throw new AgentError('refusal', refusalMessage(message.stop_details));
		}
		for (const block of message.content) {
			if (block.type !== 'text') continue;
			text += block.text;
			for (const c of block.citations || []) {
				if (c.url && !sources.has(c.url)) sources.set(c.url, { url: c.url, title: c.title || c.url });
			}
		}
		if (message.stop_reason === 'pause_turn') {
			if (turns >= MAX_TURNS) {
				truncated = true;
				break;
			}
			messages.push({ role: 'assistant', content: echoContent(message.content) });
			continue;
		}
		truncated = message.stop_reason === 'max_tokens';
		break;
	}

	if (!text.trim()) throw new AgentError('empty', 'Claude returned no text for this step.');
	return { text, sources: [...sources.values()], truncated, usage, servedBy, note };
}
