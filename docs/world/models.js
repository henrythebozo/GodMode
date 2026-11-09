/**
 * The models a mission can run on, and what they cost.
 *
 * Prices are US dollars per million tokens, from Anthropic's price list as of
 * November 2026. They are only used to show an estimate after a mission, so a
 * stale number here mislabels a figure; it never changes what is billed.
 */
export const MODELS = [
	{
		id: 'claude-opus-5-5',
		label: 'Opus 5.5',
		note: 'Most capable',
		inputPrice: 4,
		outputPrice: 20,
		fallback: true,
	},
	{
		id: 'claude-sonnet-5-5',
		label: 'Sonnet 5.5',
		note: 'Faster, half the price',
		inputPrice: 2,
		outputPrice: 10,
		fallback: true,
	},
	{
		id: 'claude-haiku-5-5',
		label: 'Haiku 5.5',
		note: 'Fastest, pennies a mission',
		inputPrice: 0.1,
		outputPrice: 0.5,
		// Haiku 5.5 has no server-side refusal fallback; sending one is an error.
		fallback: false,
	},
];

export const DEFAULT_MODEL = 'claude-opus-5-5';

export function modelById(id) {
	return (
		MODELS.find((m) => m.id === id) || MODELS.find((m) => m.id === DEFAULT_MODEL)
	);
}

export function supportsFallback(id) {
	return modelById(id).fallback;
}

/** Add one API `usage` object to a running `{ input, output, searches }` total. */
export function addUsage(total, usage) {
	const t = total || { input: 0, output: 0, searches: 0 };
	const u = usage || {};
	return {
		input: t.input + (u.input_tokens || 0),
		output: t.output + (u.output_tokens || 0),
		searches: t.searches + (u.server_tool_use?.web_search_requests || 0),
	};
}

/** Add two running totals together. */
export function mergeUsage(a, b) {
	return {
		input: a.input + b.input,
		output: a.output + b.output,
		searches: a.searches + b.searches,
	};
}

/** Token cost in dollars. Web search fees are billed separately and not included. */
export function estimateCost(total, modelId) {
	const m = modelById(modelId);
	return (
		(total.input * m.inputPrice + total.output * m.outputPrice) / 1_000_000
	);
}

export function formatCost(dollars) {
	if (dollars < 0.01) return 'under $0.01';
	return '$' + dollars.toFixed(2);
}

export function formatTokens(n) {
	if (n >= 1_000_000) return (n / 1_000_000).toFixed(1) + 'M';
	if (n >= 1000) return (n / 1000).toFixed(1) + 'k';
	return String(n);
}
