import test from 'node:test';
import assert from 'node:assert/strict';
import {
	MODELS,
	DEFAULT_MODEL,
	modelById,
	supportsFallback,
	addUsage,
	estimateCost,
	formatCost,
	formatTokens,
} from '../../docs/world/models.js';

test('the default model is one of the offered models', () => {
	assert.ok(MODELS.some((m) => m.id === DEFAULT_MODEL));
	assert.equal(DEFAULT_MODEL, 'claude-opus-5-5');
});

test('an unknown model id resolves to the default model', () => {
	assert.equal(modelById('nope').id, DEFAULT_MODEL);
	assert.equal(modelById('claude-haiku-5-5').id, 'claude-haiku-5-5');
});

test('Haiku 5.5 has no server-side fallback, Opus and Sonnet 5.5 do', () => {
	assert.equal(supportsFallback('claude-opus-5-5'), true);
	assert.equal(supportsFallback('claude-sonnet-5-5'), true);
	assert.equal(supportsFallback('claude-haiku-5-5'), false);
});

test('addUsage sums API usage objects without mutating the total', () => {
	const start = { input: 10, output: 5, searches: 0 };
	const next = addUsage(start, {
		input_tokens: 100,
		output_tokens: 40,
		server_tool_use: { web_search_requests: 2 },
	});
	assert.deepEqual(next, { input: 110, output: 45, searches: 2 });
	assert.deepEqual(start, { input: 10, output: 5, searches: 0 });
});

test('addUsage tolerates a missing usage object', () => {
	assert.deepEqual(addUsage(undefined, undefined), { input: 0, output: 0, searches: 0 });
});

test('cost is input and output tokens at the model price per million', () => {
	// Opus 5.5: $4 in, $20 out per million tokens
	const cost = estimateCost({ input: 1_000_000, output: 500_000, searches: 0 }, 'claude-opus-5-5');
	assert.equal(cost, 14);
});

test('formatCost keeps tiny amounts honest instead of showing $0.00', () => {
	assert.equal(formatCost(0.004), 'under $0.01');
	assert.equal(formatCost(0.426), '$0.43');
	assert.equal(formatCost(12), '$12.00');
});

test('formatTokens shortens thousands', () => {
	assert.equal(formatTokens(950), '950');
	assert.equal(formatTokens(12_340), '12.3k');
	assert.equal(formatTokens(2_500_000), '2.5M');
});

test('mergeUsage adds two running totals', async () => {
	const { mergeUsage } = await import('../../docs/world/models.js');
	assert.deepEqual(
		mergeUsage({ input: 1, output: 2, searches: 3 }, { input: 10, output: 20, searches: 30 }),
		{ input: 11, output: 22, searches: 33 },
	);
});
