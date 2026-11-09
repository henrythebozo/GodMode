import test from 'node:test';
import assert from 'node:assert/strict';
import { runMission } from '../../docs/world/mission.js';
import { SYSTEM } from '../../docs/world/prompts.js';
import { fakeClient, apiError, recorder } from './fake-client.mjs';

const GOAL = 'Plan a launch for my app';

const plan = (assignments) => ({
	text: [
		JSON.stringify({
			brief: 'Launch plan',
			deliverable: 'A one-page plan',
			assignments,
		}),
	],
});
const review = (approved, issues = []) => ({
	text: [
		JSON.stringify({
			approved,
			summary: approved ? 'Good.' : 'Needs work.',
			issues,
		}),
	],
});
const TWO = [
	{ agent: 'researcher', task: 'Find three competitors' },
	{ agent: 'analyst', task: 'Pick the best channel' },
];

/** A fake client whose reply depends on which agent is asking. */
function team(script) {
	const seen = {};
	const client = fakeClient((params) => {
		const role = Object.keys(SYSTEM).find((r) => SYSTEM[r] === params.system);
		seen[role] = (seen[role] || 0) + 1;
		const entry = script[role];
		return Array.isArray(entry) ? entry[seen[role] - 1] : entry;
	});
	client.callsTo = (role) =>
		client.calls.filter((c) => c.params.system === SYSTEM[role]);
	client.askedOf = (role, n = 0) =>
		client.callsTo(role)[n].params.messages[0].content;
	return client;
}

const happy = (overrides = {}) =>
	team({
		planner: plan(TWO),
		researcher: { thinking: ['Searching.'], text: ['Rivals: A, B, C.'] },
		analyst: { text: ['Use email.'] },
		engineer: { text: ['Build a page.'] },
		writer: { text: ['# The launch plan'] },
		critic: review(true),
		...overrides,
	});

const start = (client, extra = {}) => {
	const emit = recorder();
	return {
		emit,
		done: runMission({
			goal: GOAL,
			client,
			model: 'claude-opus-5-5',
			emit,
			...extra,
		}),
	};
};

test('a mission plans, works, writes, reviews, and returns the Writer’s deliverable', async () => {
	const { emit, done } = start(happy());
	const outcome = await done;
	assert.equal(outcome.status, 'done');
	assert.equal(outcome.result, '# The launch plan');
	assert.equal(outcome.revised, false);
	assert.deepEqual(
		emit.of('phase').map((e) => e.phase),
		['plan', 'work', 'write', 'review', 'done'],
	);
});

test('only the specialists the plan names are run; the rest sit the mission out', async () => {
	const client = happy();
	const { emit, done } = start(client);
	await done;
	assert.equal(client.callsTo('engineer').length, 0);
	assert.deepEqual(
		emit
			.of('state')
			.filter((e) => e.id === 'engineer')
			.map((e) => e.state),
		['skipped'],
	);
});

test('each specialist is given the mission and its own task, not the others’', async () => {
	const client = happy();
	await start(client).done;
	const asked = client.askedOf('researcher');
	assert.match(asked, /Plan a launch for my app/);
	assert.match(asked, /Find three competitors/);
	assert.doesNotMatch(asked, /Pick the best channel/);
});

test('the Writer is given the mission and every specialist’s work', async () => {
	const client = happy();
	await start(client).done;
	const asked = client.askedOf('writer');
	assert.match(asked, /Plan a launch for my app/);
	assert.match(asked, /Rivals: A, B, C\./);
	assert.match(asked, /Use email\./);
	assert.match(asked, /A one-page plan/);
});

test('the Critic is given the mission and the draft', async () => {
	const client = happy();
	await start(client).done;
	const asked = client.askedOf('critic');
	assert.match(asked, /Plan a launch for my app/);
	assert.match(asked, /# The launch plan/);
});

test('specialists work at the same time, not one after another', async () => {
	let active = 0;
	let most = 0;
	const busy = (text) => ({
		before: async () => {
			active++;
			most = Math.max(most, active);
			await new Promise((r) => setTimeout(r, 5));
			active--;
		},
		text: [text],
	});
	await start(happy({ researcher: busy('r'), analyst: busy('a') })).done;
	assert.equal(most, 2);
});

test('only the Researcher is given web search', async () => {
	const client = happy();
	await start(client).done;
	assert.deepEqual(
		client.callsTo('researcher')[0].params.tools.map((t) => t.type),
		['web_search_20260209'],
	);
	for (const role of ['planner', 'analyst', 'writer', 'critic']) {
		assert.ok(
			!('tools' in client.callsTo(role)[0].params),
			role + ' should have no tools',
		);
	}
});

test('with web search switched off, the Researcher gets no tools either', async () => {
	const client = happy();
	await start(client, { webSearch: false }).done;
	assert.ok(!('tools' in client.callsTo('researcher')[0].params));
});

test('the Planner and the Critic are held to their JSON schemas', async () => {
	const client = happy();
	await start(client).done;
	assert.equal(
		client.callsTo('planner')[0].params.output_config.format.type,
		'json_schema',
	);
	assert.equal(
		client.callsTo('critic')[0].params.output_config.format.type,
		'json_schema',
	);
	assert.ok(!client.callsTo('writer')[0].params.output_config.format);
});

test('a rejected draft is revised once, and the revision is what comes back', async () => {
	const client = happy({
		writer: [{ text: ['Draft one'] }, { text: ['Draft two'] }],
		critic: review(false, ['Add a budget']),
	});
	const { emit, done } = start(client);
	const outcome = await done;
	assert.equal(outcome.result, 'Draft two');
	assert.equal(outcome.revised, true);
	assert.equal(client.callsTo('writer').length, 2);
	assert.equal(client.callsTo('critic').length, 1);
	const asked = client.askedOf('writer', 1);
	assert.match(asked, /Add a budget/);
	assert.match(asked, /Draft one/);
	assert.deepEqual(
		emit.of('phase').map((e) => e.phase),
		['plan', 'work', 'write', 'review', 'revise', 'done'],
	);
});

test('an approved draft is not revised', async () => {
	const client = happy();
	await start(client).done;
	assert.equal(client.callsTo('writer').length, 1);
});

test('one specialist failing does not stop the mission, and the Writer is told what is missing', async () => {
	const client = happy({ researcher: { error: apiError(529, 'overloaded') } });
	const outcome = await start(client).done;
	assert.equal(outcome.status, 'done');
	assert.ok(outcome.notes.some((n) => /Researcher/.test(n)));
	assert.match(
		client.askedOf('writer'),
		/Researcher[^\n]*(could not|unavailable|missing)/i,
	);
});

test('if every assigned specialist fails, the mission fails and says why', async () => {
	const client = happy({
		researcher: { error: apiError(529, 'overloaded') },
		analyst: { error: apiError(529, 'overloaded') },
	});
	const outcome = await start(client).done;
	assert.equal(outcome.status, 'failed');
	assert.match(outcome.message, /overloaded/i);
	assert.equal(client.callsTo('writer').length, 0);
});

test('a rejected key fails the mission at the first step, with the key message', async () => {
	const client = happy({
		planner: { error: apiError(401, 'invalid x-api-key') },
	});
	const outcome = await start(client).done;
	assert.equal(outcome.status, 'failed');
	assert.match(outcome.message, /key/i);
	assert.equal(client.calls.length, 1);
});

test('an unreadable plan puts all three specialists on the mission and says so', async () => {
	const client = happy({ planner: { text: ['Here is my plan, in prose.'] } });
	const outcome = await start(client).done;
	assert.equal(outcome.status, 'done');
	for (const role of ['researcher', 'analyst', 'engineer'])
		assert.equal(client.callsTo(role).length, 1);
	assert.ok(outcome.notes.some((n) => /plan/i.test(n)));
});

test('a declined plan also falls back instead of failing the mission', async () => {
	const client = happy({ planner: { content: [], stop: 'refusal' } });
	const outcome = await start(client).done;
	assert.equal(outcome.status, 'done');
	assert.equal(client.callsTo('engineer').length, 1);
});

test('a plan with no assignments sends the mission straight to the Writer', async () => {
	const client = happy({ planner: plan([]) });
	const outcome = await start(client).done;
	assert.equal(outcome.status, 'done');
	for (const role of ['researcher', 'analyst', 'engineer'])
		assert.equal(client.callsTo(role).length, 0);
});

test('if the Critic fails, the draft is kept and the result says it went unreviewed', async () => {
	const client = happy({ critic: { error: apiError(529, 'overloaded') } });
	const outcome = await start(client).done;
	assert.equal(outcome.status, 'done');
	assert.equal(outcome.result, '# The launch plan');
	assert.ok(outcome.notes.some((n) => /unreviewed/i.test(n)));
});

test('if the revision fails, the first draft is kept and the result says so', async () => {
	const client = happy({
		writer: [{ text: ['Draft one'] }, { error: apiError(529, 'overloaded') }],
		critic: review(false, ['Add a budget']),
	});
	const outcome = await start(client).done;
	assert.equal(outcome.status, 'done');
	assert.equal(outcome.result, 'Draft one');
	assert.equal(outcome.revised, false);
	assert.ok(outcome.notes.some((n) => /first draft/i.test(n)));
});

test('if the Writer fails, the mission fails', async () => {
	const client = happy({ writer: { error: apiError(529, 'overloaded') } });
	const outcome = await start(client).done;
	assert.equal(outcome.status, 'failed');
	assert.equal(client.callsTo('critic').length, 0);
});

test('stopping mid-mission ends it as stopped and starts nothing further', async () => {
	const controller = new AbortController();
	const client = happy({
		researcher: { before: async () => controller.abort(), text: ['never'] },
	});
	const { emit, done } = start(client, { signal: controller.signal });
	const outcome = await done;
	assert.equal(outcome.status, 'stopped');
	assert.equal(client.callsTo('writer').length, 0);
	assert.equal(emit.of('phase').at(-1).phase, 'stopped');
});

test('work is handed along the paths in the order it flows', async () => {
	const { emit, done } = start(happy());
	await done;
	assert.deepEqual(
		emit.of('handoff').map((e) => `${e.from}>${e.to}`),
		[
			'planner>researcher',
			'planner>analyst',
			'researcher>writer',
			'analyst>writer',
			'writer>critic',
			'writer>plaza',
		],
	);
});

test('a rejected draft travels back from the Critic to the Writer', async () => {
	const client = happy({
		writer: [{ text: ['one'] }, { text: ['two'] }],
		critic: review(false, ['Fix it']),
	});
	const { emit, done } = start(client);
	await done;
	const hops = emit.of('handoff').map((e) => `${e.from}>${e.to}`);
	assert.deepEqual(hops.slice(-3), [
		'writer>critic',
		'critic>writer',
		'writer>plaza',
	]);
});

test('a specialist goes queued, thinking, writing, done', async () => {
	const { emit, done } = start(happy());
	await done;
	assert.deepEqual(
		emit
			.of('state')
			.filter((e) => e.id === 'researcher')
			.map((e) => e.state),
		['queued', 'thinking', 'writing', 'done'],
	);
});

test('each agent’s reasoning and text are streamed under its own id', async () => {
	const { emit, done } = start(happy());
	await done;
	assert.deepEqual(
		emit
			.of('thinking')
			.filter((e) => e.id === 'researcher')
			.map((e) => e.delta),
		['Searching.'],
	);
	assert.deepEqual(
		emit
			.of('text')
			.filter((e) => e.id === 'writer')
			.map((e) => e.delta),
		['# The launch plan'],
	);
});

test('the Planner and Critic show a readable summary instead of streaming raw JSON', async () => {
	const { emit, done } = start(happy());
	await done;
	assert.equal(
		emit.of('text').filter((e) => e.id === 'planner' || e.id === 'critic')
			.length,
		0,
	);
	const shown = emit.of('output').find((e) => e.id === 'planner').markdown;
	assert.match(shown, /Researcher/);
	assert.doesNotMatch(shown, /\{/);
	assert.match(
		emit.of('output').find((e) => e.id === 'critic').markdown,
		/Approved/,
	);
});

test('every agent is told what it was asked, for the Brief tab', async () => {
	const { emit, done } = start(happy());
	await done;
	assert.match(
		emit.of('brief').find((e) => e.id === 'researcher').text,
		/Find three competitors/,
	);
	assert.match(
		emit.of('brief').find((e) => e.id === 'planner').text,
		/Plan a launch for my app/,
	);
});

test('sources the Researcher cited are appended to its work and reach the Writer', async () => {
	const client = happy({
		researcher: {
			content: [
				{
					type: 'text',
					text: 'Rival A is big.',
					citations: [
						{
							type: 'web_search_result_location',
							url: 'https://a.example/x',
							title: 'About A',
						},
					],
				},
			],
		},
	});
	const { emit, done } = start(client);
	await done;
	assert.match(
		emit.of('output').find((e) => e.id === 'researcher').markdown,
		/\[About A\]\(https:\/\/a\.example\/x\)/,
	);
	assert.match(client.askedOf('writer'), /https:\/\/a\.example\/x/);
});

test('token usage is totalled across every call', async () => {
	const client = happy(); // six agents minus the engineer = five calls at 10 in / 20 out
	const outcome = await start(client).done;
	assert.deepEqual(outcome.usage, { input: 50, output: 100, searches: 0 });
});

test('the plan and the review are returned with the result', async () => {
	const outcome = await start(happy()).done;
	assert.equal(outcome.plan.assignments.length, 2);
	assert.equal(outcome.review.approved, true);
});
