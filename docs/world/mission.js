/**
 * Runs one mission through the team: plan, work, write, review, done.
 *
 * No DOM and no three.js in here. The page learns what is happening only
 * through the events passed to `emit`, which is also how the tests watch it:
 *
 *   { type: 'phase', phase }          plan | work | write | review | revise | done | stopped | failed
 *   { type: 'state', id, state }      queued | thinking | writing | done | skipped | error
 *   { type: 'brief', id, text }       what that agent was asked
 *   { type: 'thinking', id, delta }   streamed reasoning summary
 *   { type: 'text', id, delta }       streamed answer (not sent for the JSON agents)
 *   { type: 'tool', id, name, query } a web search
 *   { type: 'restart', id }           the agent is starting over (the Writer's revision)
 *   { type: 'output', id, markdown }  the agent's finished work, ready to show
 *   { type: 'usage', id, usage }      tokens used by one call
 *   { type: 'note', id?, text }       something the person should know
 *   { type: 'handoff', from, to }     work travelling between buildings
 */
import { runAgent, AgentError } from './agent-run.js';
import { addUsage, mergeUsage } from './models.js';
import { PLAN_SCHEMA, REVIEW_SCHEMA, parsePlan, parseReview, planToMarkdown, reviewToMarkdown } from './plan.js';
import { SYSTEM, plannerMessage, specialistMessage, writerMessage, criticMessage, revisionMessage } from './prompts.js';
import { SPECIALISTS, PLAZA, agentById } from './roster.js';

const WEB_SEARCH = { type: 'web_search_20260209', name: 'web_search', max_uses: 5 };

// How hard each role thinks and how much room it gets. The Planner is a
// routing decision; the Writer may be producing a long document.
const SETTINGS = {
	planner: { effort: 'low', maxTokens: 8000 },
	researcher: { effort: 'medium', maxTokens: 16000 },
	analyst: { effort: 'medium', maxTokens: 16000 },
	engineer: { effort: 'medium', maxTokens: 16000 },
	writer: { effort: 'medium', maxTokens: 32000 },
	critic: { effort: 'medium', maxTokens: 8000 },
};

const nameOf = (id) => agentById(id)?.name || id;

// A stopped run or a rejected key ends the whole mission; nothing after it could succeed.
const endsMission = (err) => err?.kind === 'aborted' || err?.kind === 'auth';

function withSources(out) {
	if (!out.sources.length) return out.text;
	const links = out.sources.map((s) => `- [${s.title.replace(/[[\]]/g, '')}](${s.url})`);
	return `${out.text}\n\n**Sources**\n\n${links.join('\n')}`;
}

export async function runMission({ goal, client, model, emit = () => {}, signal, today = '', webSearch = true }) {
	const notes = [];
	let usage = addUsage();
	let plan = null;
	let review = null;
	let revised = false;

	const note = (text, id) => {
		notes.push(text);
		emit({ type: 'note', id, text });
	};

	/** One agent call. `quiet` keeps raw JSON out of the text stream. */
	const run = async (id, { user, brief, schema, tools, quiet = false }) => {
		emit({ type: 'brief', id, text: brief });
		emit({ type: 'state', id, state: 'thinking' });
		let writing = false;
		try {
			const out = await runAgent({
				client,
				model,
				system: SYSTEM[id],
				user,
				schema,
				tools,
				signal,
				...SETTINGS[id],
				emit: (event) => {
					if (event.type === 'note') notes.push(event.text);
					if (event.type === 'text') {
						if (!writing) {
							writing = true;
							emit({ type: 'state', id, state: 'writing' });
						}
						if (quiet) return;
					}
					emit({ ...event, id });
				},
			});
			usage = mergeUsage(usage, out.usage);
			emit({ type: 'usage', id, usage: out.usage });
			if (out.truncated) note(`${nameOf(id)} ran out of room, so its work is cut short.`, id);
			return out;
		} catch (err) {
			if (err?.kind !== 'aborted') emit({ type: 'state', id, state: 'error' });
			throw err;
		}
	};

	const finish = (id, markdown) => {
		emit({ type: 'output', id, markdown });
		emit({ type: 'state', id, state: 'done' });
	};

	const outcome = (status, extra = {}) => {
		emit({ type: 'phase', phase: status });
		return { status, plan, review, revised, notes, usage, ...extra };
	};

	try {
		// 1. Plan
		emit({ type: 'phase', phase: 'plan' });
		try {
			const out = await run('planner', {
				user: plannerMessage({ goal, today }),
				brief: goal,
				schema: PLAN_SCHEMA,
				quiet: true,
			});
			plan = parsePlan(out.text, goal);
		} catch (err) {
			// A declined or empty plan can be worked around. Anything else at the
			// very first step (bad key, rate limit, no network) would fail every
			// later step too, so stop here with that message.
			if (err?.kind !== 'refusal' && err?.kind !== 'empty') throw err;
			plan = parsePlan('', goal);
		}
		if (plan.fallback) {
			note('The Planner’s plan could not be read, so every specialist worked the mission directly.', 'planner');
		}
		finish('planner', planToMarkdown(plan));

		// 2. Work — the assigned specialists, all at once
		emit({ type: 'phase', phase: 'work' });
		const assigned = plan.assignments;
		for (const id of SPECIALISTS) {
			if (!assigned.some((a) => a.agent === id)) emit({ type: 'state', id, state: 'skipped' });
		}
		for (const { agent } of assigned) {
			emit({ type: 'state', id: agent, state: 'queued' });
			emit({ type: 'handoff', from: 'planner', to: agent });
		}
		if (!assigned.length) emit({ type: 'handoff', from: 'planner', to: 'writer' });

		const settled = await Promise.all(
			assigned.map(async ({ agent, task }) => {
				try {
					const out = await run(agent, {
						user: specialistMessage({ goal, task, today }),
						brief: task,
						tools: agent === 'researcher' && webSearch ? [WEB_SEARCH] : null,
					});
					const text = withSources(out);
					finish(agent, text);
					emit({ type: 'handoff', from: agent, to: 'writer' });
					return { agent, text };
				} catch (err) {
					return { agent, err };
				}
			}),
		);
		const ending = settled.find((s) => endsMission(s.err));
		if (ending) throw ending.err;
		const failures = settled.filter((s) => s.err);
		if (assigned.length && failures.length === assigned.length) throw failures[0].err;
		for (const { agent, err } of failures) {
			note(`${nameOf(agent)} could not finish: ${err.message}`, agent);
		}
		const work = settled.map(({ agent, text, err }) => (err ? { agent, failed: err.message } : { agent, text }));

		// 3. Write
		emit({ type: 'phase', phase: 'write' });
		const first = await run('writer', {
			user: writerMessage({ goal, plan, work, today }),
			brief: plan.deliverable,
		});
		let draft = first.text;
		finish('writer', draft);

		// 4. Review, and at most one revision
		emit({ type: 'phase', phase: 'review' });
		emit({ type: 'handoff', from: 'writer', to: 'critic' });
		try {
			const out = await run('critic', {
				user: criticMessage({ goal, plan, work, draft }),
				brief: 'Review the Writer’s draft against the mission.',
				schema: REVIEW_SCHEMA,
				quiet: true,
			});
			review = parseReview(out.text);
			if (review.fallback) note('The Critic’s review could not be read, so the draft went through unreviewed.', 'critic');
			finish('critic', reviewToMarkdown(review));
		} catch (err) {
			if (endsMission(err)) throw err;
			note(`The Critic could not review the draft (${err.message}), so it went through unreviewed.`, 'critic');
		}

		if (review && !review.approved) {
			emit({ type: 'phase', phase: 'revise' });
			emit({ type: 'handoff', from: 'critic', to: 'writer' });
			emit({ type: 'restart', id: 'writer' });
			try {
				const out = await run('writer', {
					user: revisionMessage({ goal, plan, work, draft, review, today }),
					brief: `Revise the draft. The Critic asked for:\n\n${review.issues.map((i) => `- ${i}`).join('\n')}`,
				});
				draft = out.text;
				revised = true;
			} catch (err) {
				if (endsMission(err)) throw err;
				note(`The revision failed (${err.message}), so this is the first draft.`, 'writer');
			}
			finish('writer', draft);
		}

		// 5. Done
		emit({ type: 'handoff', from: 'writer', to: PLAZA });
		return outcome('done', { result: draft });
	} catch (err) {
		if (err?.kind === 'aborted' || signal?.aborted) return outcome('stopped');
		const message = err instanceof AgentError ? err.message : `Something went wrong: ${err?.message || err}`;
		return outcome('failed', { message });
	}
}
