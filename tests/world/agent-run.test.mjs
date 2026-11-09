import test from 'node:test';
import assert from 'node:assert/strict';
import { runAgent, echoContent, AgentError } from '../../docs/world/agent-run.js';
import { fakeClient, apiError, recorder } from './fake-client.mjs';

const BASE = { model: 'claude-opus-5-5', system: 'You are a tester.', user: 'Do the thing.' };

test('reasoning and text deltas are emitted as they arrive, and the full text is returned', async () => {
	const client = fakeClient([{ thinking: ['Let me ', 'think.'], text: ['Hello ', 'world'] }]);
	const emit = recorder();
	const result = await runAgent({ ...BASE, client, emit });
	assert.deepEqual(emit.of('thinking').map((e) => e.delta), ['Let me ', 'think.']);
	assert.deepEqual(emit.of('text').map((e) => e.delta), ['Hello ', 'world']);
	assert.equal(result.text, 'Hello world');
	assert.equal(result.truncated, false);
});

test('the request asks for summarized adaptive thinking, so the reasoning is visible', async () => {
	const client = fakeClient([{ text: ['ok'] }]);
	await runAgent({ ...BASE, client });
	assert.deepEqual(client.calls[0].params.thinking, { type: 'adaptive', display: 'summarized' });
});

test('effort is set explicitly rather than left to the model default', async () => {
	const client = fakeClient([{ text: ['ok'] }, { text: ['ok'] }]);
	await runAgent({ ...BASE, client });
	await runAgent({ ...BASE, client, effort: 'low' });
	assert.equal(client.calls[0].params.output_config.effort, 'medium');
	assert.equal(client.calls[1].params.output_config.effort, 'low');
});

test('Opus 5.5 requests carry the server-side refusal fallback', async () => {
	const client = fakeClient([{ text: ['ok'] }]);
	await runAgent({ ...BASE, client });
	assert.equal(client.calls[0].params.fallbacks, 'default');
	assert.deepEqual(client.calls[0].params.betas, ['server-side-fallback-2026-07-01']);
});

test('Haiku 5.5 requests do not, because it has no server-side fallback', async () => {
	const client = fakeClient([{ text: ['ok'] }]);
	await runAgent({ ...BASE, client, model: 'claude-haiku-5-5' });
	assert.ok(!('fallbacks' in client.calls[0].params));
	assert.ok(!('betas' in client.calls[0].params));
});

test('a JSON agent sends its schema as the output format', async () => {
	const schema = { type: 'object', properties: {}, additionalProperties: false };
	const client = fakeClient([{ text: ['{}'] }]);
	await runAgent({ ...BASE, client, schema });
	assert.deepEqual(client.calls[0].params.output_config.format, { type: 'json_schema', schema });
});

test('the caller’s abort signal reaches the request', async () => {
	const client = fakeClient([{ text: ['ok'] }]);
	const controller = new AbortController();
	await runAgent({ ...BASE, client, signal: controller.signal });
	assert.equal(client.calls[0].options.signal, controller.signal);
});

test('a paused web-search turn is resumed by sending the assistant turn back', async () => {
	const search = { type: 'server_tool_use', id: 'srv_1', name: 'web_search', input: { query: 'x' } };
	const client = fakeClient([
		{ blocks: [search], text: ['Part one. '], stop: 'pause_turn', usage: { input_tokens: 5, output_tokens: 7 } },
		{ text: ['Part two.'], usage: { input_tokens: 3, output_tokens: 4 } },
	]);
	const result = await runAgent({ ...BASE, client, tools: [{ type: 'web_search_20260209', name: 'web_search' }] });
	assert.equal(client.calls.length, 2);
	const resumed = client.calls[1].params.messages;
	assert.equal(resumed.length, 2);
	assert.equal(resumed[1].role, 'assistant');
	assert.deepEqual(resumed[1].content[0], search);
	assert.equal(result.text, 'Part one. Part two.');
	assert.deepEqual(result.usage, { input: 8, output: 11, searches: 0 });
});

test('a turn that keeps pausing is cut off rather than resumed forever', async () => {
	const client = fakeClient(() => ({ text: ['more '], stop: 'pause_turn' }));
	const result = await runAgent({ ...BASE, client });
	assert.equal(client.calls.length, 5);
	assert.equal(result.truncated, true);
});

test('when resuming after a fallback, reasoning and unpaired tool calls before the switch are dropped', () => {
	const paired = { type: 'server_tool_use', id: 'srv_1', name: 'web_search', input: {} };
	const result = { type: 'web_search_tool_result', tool_use_id: 'srv_1', content: [] };
	const unpaired = { type: 'server_tool_use', id: 'srv_2', name: 'web_search', input: {} };
	const fallback = { type: 'fallback', from: { model: 'a' }, to: { model: 'b' } };
	const after = { type: 'thinking', thinking: 'later', signature: 's' };
	const echoed = echoContent([
		{ type: 'thinking', thinking: 'early', signature: 's' },
		paired,
		result,
		unpaired,
		{ type: 'text', text: 'partial' },
		fallback,
		after,
		{ type: 'text', text: 'rest' },
	]);
	assert.deepEqual(echoed, [paired, result, { type: 'text', text: 'partial' }, fallback, after, { type: 'text', text: 'rest' }]);
});

test('content without a fallback switch is echoed back unchanged', () => {
	const content = [{ type: 'thinking', thinking: 't', signature: 's' }, { type: 'text', text: 'x' }];
	assert.deepEqual(echoContent(content), content);
});

test('a refusal is reported as a refusal instead of being returned as an answer', async () => {
	const client = fakeClient([{ content: [], stop: 'refusal', stopDetails: { category: 'cyber' } }]);
	await assert.rejects(runAgent({ ...BASE, client }), (err) => {
		assert.ok(err instanceof AgentError);
		assert.equal(err.kind, 'refusal');
		return true;
	});
});

test('if the API rejects a request that has tools, it is retried once without them and says so', async () => {
	const client = fakeClient([{ error: apiError(400, 'web search is not enabled') }, { text: ['From memory.'] }]);
	const emit = recorder();
	const result = await runAgent({ ...BASE, client, emit, tools: [{ type: 'web_search_20260209', name: 'web_search' }] });
	assert.equal(client.calls.length, 2);
	assert.ok(!('tools' in client.calls[1].params));
	assert.equal(result.text, 'From memory.');
	assert.equal(emit.of('note').length, 1);
	assert.match(result.note, /web search/i);
});

test('a rejected request without tools is not retried', async () => {
	const client = fakeClient([{ error: apiError(400, 'bad request') }]);
	await assert.rejects(runAgent({ ...BASE, client }), (err) => err.kind === 'api');
	assert.equal(client.calls.length, 1);
});

test('a rejected key fails with a message that says where to fix it', async () => {
	const client = fakeClient([{ error: apiError(401, 'invalid x-api-key') }]);
	await assert.rejects(runAgent({ ...BASE, client }), (err) => {
		assert.equal(err.kind, 'auth');
		assert.match(err.message, /key/i);
		assert.match(err.message, /settings/i);
		return true;
	});
});

test('a rate limit says to wait rather than echoing a raw status', async () => {
	const client = fakeClient([{ error: apiError(429, '429 rate_limit_error') }]);
	await assert.rejects(runAgent({ ...BASE, client }), (err) => err.kind === 'api' && /rate limit/i.test(err.message));
});

test('an aborted run rejects as aborted, whatever error the client threw', async () => {
	const controller = new AbortController();
	const client = fakeClient([{ before: async () => controller.abort(), text: ['never'] }]);
	await assert.rejects(runAgent({ ...BASE, client, signal: controller.signal }), (err) => err.kind === 'aborted');
});

test('web searches are surfaced as tool events with their query', async () => {
	const client = fakeClient([
		{ blocks: [{ type: 'server_tool_use', id: 's1', name: 'web_search', input: { query: 'henry os' } }], text: ['Found it.'] },
	]);
	const emit = recorder();
	await runAgent({ ...BASE, client, emit });
	assert.deepEqual(emit.of('tool'), [{ type: 'tool', name: 'web_search', query: 'henry os' }]);
});

test('cited web sources are collected once each', async () => {
	const cite = (url, title) => ({ type: 'web_search_result_location', url, title, cited_text: '…' });
	const client = fakeClient([
		{
			content: [
				{ type: 'text', text: 'A. ', citations: [cite('https://a.example', 'A')] },
				{ type: 'text', text: 'B.', citations: [cite('https://a.example', 'A'), cite('https://b.example', 'B')] },
			],
		},
	]);
	const result = await runAgent({ ...BASE, client });
	assert.equal(result.text, 'A. B.');
	assert.deepEqual(result.sources, [
		{ url: 'https://a.example', title: 'A' },
		{ url: 'https://b.example', title: 'B' },
	]);
});

test('running out of tokens returns the partial text, flagged as truncated', async () => {
	const client = fakeClient([{ text: ['Half an ans'], stop: 'max_tokens' }]);
	const result = await runAgent({ ...BASE, client });
	assert.equal(result.text, 'Half an ans');
	assert.equal(result.truncated, true);
});

test('a reply with no text is an error, not an empty success', async () => {
	const client = fakeClient([{ content: [{ type: 'thinking', thinking: 'hm', signature: 's' }] }]);
	await assert.rejects(runAgent({ ...BASE, client }), (err) => err.kind === 'empty');
});

test('the model that actually served the reply is reported', async () => {
	const client = fakeClient([{ text: ['ok'], model: 'claude-opus-4-8' }]);
	const result = await runAgent({ ...BASE, client });
	assert.equal(result.servedBy, 'claude-opus-4-8');
});

test('a server-side switch to another model is surfaced as a note', async () => {
	const client = fakeClient([
		{
			blocks: [{ type: 'fallback', from: { model: 'claude-opus-5-5' }, to: { model: 'claude-opus-4-8' } }],
			text: ['ok'],
		},
	]);
	const emit = recorder();
	await runAgent({ ...BASE, client, emit });
	assert.equal(emit.of('note').length, 1);
	assert.match(emit.of('note')[0].text, /claude-opus-4-8/);
});
