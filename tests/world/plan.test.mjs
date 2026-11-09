import test from 'node:test';
import assert from 'node:assert/strict';
import {
	PLAN_SCHEMA,
	REVIEW_SCHEMA,
	parsePlan,
	parseReview,
	planToMarkdown,
	reviewToMarkdown,
} from '../../docs/world/plan.js';

const GOAL = 'Plan a launch for my app';

test('a valid plan keeps its brief, deliverable and assignments', () => {
	const plan = parsePlan(
		JSON.stringify({
			brief: 'Launch plan',
			deliverable: 'A one-page plan',
			assignments: [
				{ agent: 'researcher', task: 'Find competitors' },
				{ agent: 'analyst', task: 'Pick a channel' },
			],
		}),
		GOAL,
	);
	assert.equal(plan.fallback, false);
	assert.equal(plan.brief, 'Launch plan');
	assert.equal(plan.deliverable, 'A one-page plan');
	assert.deepEqual(plan.assignments, [
		{ agent: 'researcher', task: 'Find competitors' },
		{ agent: 'analyst', task: 'Pick a channel' },
	]);
});

test('assignments to agents that are not specialists are dropped', () => {
	const plan = parsePlan(
		JSON.stringify({
			brief: 'b',
			deliverable: 'd',
			assignments: [
				{ agent: 'writer', task: 'Write it' },
				{ agent: 'wizard', task: 'Magic' },
				{ agent: 'engineer', task: 'Build it' },
			],
		}),
		GOAL,
	);
	assert.deepEqual(plan.assignments, [{ agent: 'engineer', task: 'Build it' }]);
});

test('a specialist assigned twice gets one combined task', () => {
	const plan = parsePlan(
		JSON.stringify({
			brief: 'b',
			deliverable: 'd',
			assignments: [
				{ agent: 'analyst', task: 'First' },
				{ agent: 'analyst', task: 'Second' },
			],
		}),
		GOAL,
	);
	assert.equal(plan.assignments.length, 1);
	assert.match(plan.assignments[0].task, /First/);
	assert.match(plan.assignments[0].task, /Second/);
});

test('blank tasks are dropped', () => {
	const plan = parsePlan(
		JSON.stringify({ brief: 'b', deliverable: 'd', assignments: [{ agent: 'analyst', task: '   ' }] }),
		GOAL,
	);
	assert.deepEqual(plan.assignments, []);
	assert.equal(plan.fallback, false);
});

test('a readable plan with no assignments is allowed: the Writer works alone', () => {
	const plan = parsePlan(JSON.stringify({ brief: 'b', deliverable: 'A haiku', assignments: [] }), GOAL);
	assert.equal(plan.fallback, false);
	assert.deepEqual(plan.assignments, []);
});

test('an unreadable plan falls back to every specialist working the mission', () => {
	const plan = parsePlan('Sorry, here is my plan in prose.', GOAL);
	assert.equal(plan.fallback, true);
	assert.deepEqual(
		plan.assignments.map((a) => a.agent),
		['researcher', 'analyst', 'engineer'],
	);
	for (const a of plan.assignments) assert.match(a.task, /Plan a launch for my app/);
});

test('a plan wrapped in a code fence is still read', () => {
	const plan = parsePlan(
		'```json\n' + JSON.stringify({ brief: 'b', deliverable: 'd', assignments: [{ agent: 'analyst', task: 't' }] }) + '\n```',
		GOAL,
	);
	assert.equal(plan.fallback, false);
	assert.equal(plan.assignments[0].agent, 'analyst');
});

test('a review that rejects with issues is kept as a rejection', () => {
	const review = parseReview(JSON.stringify({ approved: false, summary: 'Two gaps', issues: ['No budget', ' '] }));
	assert.equal(review.approved, false);
	assert.deepEqual(review.issues, ['No budget']);
	assert.equal(review.fallback, false);
});

test('a rejection with nothing actionable counts as approved', () => {
	const review = parseReview(JSON.stringify({ approved: false, summary: 'Meh', issues: [] }));
	assert.equal(review.approved, true);
});

test('an unreadable review approves the draft and says it could not be read', () => {
	const review = parseReview('not json');
	assert.equal(review.approved, true);
	assert.equal(review.fallback, true);
	assert.deepEqual(review.issues, []);
});

test('both schemas forbid extra properties, as structured outputs require', () => {
	assert.equal(PLAN_SCHEMA.additionalProperties, false);
	assert.equal(REVIEW_SCHEMA.additionalProperties, false);
	assert.equal(PLAN_SCHEMA.properties.assignments.items.additionalProperties, false);
	assert.deepEqual(PLAN_SCHEMA.properties.assignments.items.properties.agent.enum, [
		'researcher',
		'analyst',
		'engineer',
	]);
});

test('planToMarkdown names each assigned specialist', () => {
	const md = planToMarkdown({
		brief: 'Launch plan',
		deliverable: 'One page',
		assignments: [{ agent: 'researcher', task: 'Find competitors' }],
		fallback: false,
	});
	assert.match(md, /Launch plan/);
	assert.match(md, /Researcher/);
	assert.match(md, /Find competitors/);
});

test('reviewToMarkdown lists the issues of a rejection', () => {
	const md = reviewToMarkdown({ approved: false, summary: 'Two gaps', issues: ['No budget'], fallback: false });
	assert.match(md, /Two gaps/);
	assert.match(md, /No budget/);
});
