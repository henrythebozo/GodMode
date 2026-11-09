/**
 * The two structured hand-offs of a mission: the Planner's plan and the
 * Critic's review. Each has a JSON schema (sent to the API so the reply is
 * constrained to it) and a parser that still copes when the reply is not the
 * JSON asked for — a declined or truncated reply should bend the mission, not
 * break it.
 */
import { SPECIALISTS, agentById } from './roster.js';

export const PLAN_SCHEMA = {
	type: 'object',
	properties: {
		brief: {
			type: 'string',
			description: 'One or two sentences: what this mission is really asking for.',
		},
		deliverable: {
			type: 'string',
			description:
				'What the Writer should produce for the person: form, rough length, audience.',
		},
		assignments: {
			type: 'array',
			description:
				'One entry per specialist that is needed. Leave a specialist out if it adds nothing.',
			items: {
				type: 'object',
				properties: {
					agent: { type: 'string', enum: [...SPECIALISTS] },
					task: {
						type: 'string',
						description: 'A self-contained task for that specialist.',
					},
				},
				required: ['agent', 'task'],
				additionalProperties: false,
			},
		},
	},
	required: ['brief', 'deliverable', 'assignments'],
	additionalProperties: false,
};

export const REVIEW_SCHEMA = {
	type: 'object',
	properties: {
		approved: { type: 'boolean' },
		summary: {
			type: 'string',
			description: 'One or two sentences on how well the draft serves the mission.',
		},
		issues: {
			type: 'array',
			description: 'Concrete fixes the Writer must make. Empty when approved.',
			items: { type: 'string' },
		},
	},
	required: ['approved', 'summary', 'issues'],
	additionalProperties: false,
};

function readJson(text) {
	const s = String(text || '');
	const start = s.indexOf('{');
	const end = s.lastIndexOf('}');
	if (start === -1 || end <= start) return null;
	try {
		const value = JSON.parse(s.slice(start, end + 1));
		return value && typeof value === 'object' && !Array.isArray(value)
			? value
			: null;
	} catch {
		return null;
	}
}

const clean = (v) => (typeof v === 'string' ? v.trim() : '');

/**
 * Read the Planner's reply. A readable plan is taken at its word, including
 * one with no assignments (the Writer can handle a simple mission alone). An
 * unreadable one falls back to every specialist working the mission itself.
 */
export function parsePlan(text, goal) {
	const data = readJson(text);
	if (!data || !Array.isArray(data.assignments)) {
		return {
			brief: goal,
			deliverable: 'A clear, complete answer to the mission.',
			assignments: SPECIALISTS.map((agent) => ({
				agent,
				task: `Contribute what your role can to this mission: ${goal}`,
			})),
			fallback: true,
		};
	}
	const byAgent = new Map();
	for (const item of data.assignments) {
		const agent = clean(item?.agent);
		const task = clean(item?.task);
		if (!SPECIALISTS.includes(agent) || !task) continue;
		byAgent.set(agent, byAgent.has(agent) ? byAgent.get(agent) + '\n\n' + task : task);
	}
	return {
		brief: clean(data.brief) || goal,
		deliverable:
			clean(data.deliverable) || 'A clear, complete answer to the mission.',
		// keep the roster's order so the town lights up the same way every time
		assignments: SPECIALISTS.filter((a) => byAgent.has(a)).map((agent) => ({
			agent,
			task: byAgent.get(agent),
		})),
		fallback: false,
	};
}

/**
 * Read the Critic's reply. A rejection only counts if it names something to
 * fix; an unreadable review lets the draft through and is flagged as such.
 */
export function parseReview(text) {
	const data = readJson(text);
	if (!data || typeof data.approved !== 'boolean') {
		return { approved: true, summary: '', issues: [], fallback: true };
	}
	const issues = (Array.isArray(data.issues) ? data.issues : [])
		.map(clean)
		.filter(Boolean);
	return {
		approved: data.approved || issues.length === 0,
		summary: clean(data.summary),
		issues,
		fallback: false,
	};
}

export function planToMarkdown(plan) {
	const lines = [plan.brief, '', `**Deliverable:** ${plan.deliverable}`, ''];
	if (plan.fallback) {
		lines.push('*The plan could not be read, so every specialist is working the mission directly.*', '');
	}
	if (!plan.assignments.length) {
		lines.push('No specialist is needed. The Writer takes this one alone.');
	}
	for (const a of plan.assignments) {
		lines.push(`- **${agentById(a.agent)?.name || a.agent}:** ${a.task}`);
	}
	return lines.join('\n');
}

export function reviewToMarkdown(review) {
	if (review.fallback) {
		return 'The review could not be read, so the draft went through unreviewed.';
	}
	const lines = [
		review.approved ? '**Approved.**' : '**Sent back for changes.**',
		'',
		review.summary,
	];
	if (review.issues.length) {
		lines.push('');
		for (const issue of review.issues) lines.push(`- ${issue}`);
	}
	return lines.join('\n').trim();
}
