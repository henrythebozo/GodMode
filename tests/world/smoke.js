/**
 * End-to-end smoke run of the World page in a real browser.
 *
 * Serves docs/, answers every call to api.anthropic.com with a canned stream
 * (so it needs no key and spends nothing), runs one mission on a phone-sized
 * and a desktop-sized screen, and checks the page did what a person would see.
 *
 * Usage: npm run smoke:world [-- --shots <dir>]
 * Needs Playwright (`npm i -D playwright && npx playwright install chromium`).
 */
const { spawn } = require('child_process');
const fs = require('fs');
const path = require('path');

let chromium;
try {
	({ chromium } = require('playwright'));
} catch {
	console.error(
		'Playwright is not installed. Run: npm i -D playwright && npx playwright install chromium',
	);
	process.exit(2);
}

const PORT = process.env.PORT || 8761;
const BASE = `http://127.0.0.1:${PORT}`;
const shotsAt = process.argv.indexOf('--shots');
const SHOTS = shotsAt > -1 ? process.argv[shotsAt + 1] : null;

const CORS = {
	'access-control-allow-origin': '*',
	'access-control-allow-headers': '*',
	'access-control-allow-methods': 'POST, OPTIONS',
};

const REPLIES = {
	Planner: {
		thinking:
			'This needs current facts and a recommendation. No code involved.',
		text: JSON.stringify({
			brief: 'A short launch plan for a small app.',
			deliverable: 'A one-page plan with a recommendation.',
			assignments: [
				{
					agent: 'researcher',
					task: 'Find three comparable launches and what worked.',
				},
				{ agent: 'analyst', task: 'Recommend one launch channel and say why.' },
			],
		}),
	},
	Researcher: {
		thinking: 'Looking for comparable launches before drawing any conclusion.',
		text: 'Three comparable launches leaned on a waitlist.\n\n- Launch A grew by referral\n- Launch B used a demo video',
	},
	Analyst: {
		thinking: 'Comparing channels on cost and reach.',
		text: 'Recommend **email to a waitlist**: lowest cost, highest intent.',
	},
	Engineer: { thinking: 'n/a', text: 'n/a' },
	Writer: {
		thinking: 'Opening with the recommendation, then the evidence.',
		text: '# Launch plan\n\nStart with a **waitlist email**.\n\n| Channel | Cost |\n| --- | --- |\n| Email | Low |\n\n<script>window.pwned = true</script>',
	},
	Critic: {
		thinking: 'Checking the draft against the mission.',
		text: JSON.stringify({
			approved: true,
			summary: 'Clear and complete.',
			issues: [],
		}),
	},
};

function sse(model, reply) {
	const events = [
		[
			'message_start',
			{
				type: 'message_start',
				message: {
					id: 'msg_smoke',
					type: 'message',
					role: 'assistant',
					model,
					content: [],
					stop_reason: null,
					stop_sequence: null,
					usage: { input_tokens: 120, output_tokens: 1 },
				},
			},
		],
		[
			'content_block_start',
			{
				type: 'content_block_start',
				index: 0,
				content_block: { type: 'thinking', thinking: '', signature: '' },
			},
		],
		[
			'content_block_delta',
			{
				type: 'content_block_delta',
				index: 0,
				delta: { type: 'thinking_delta', thinking: reply.thinking },
			},
		],
		[
			'content_block_delta',
			{
				type: 'content_block_delta',
				index: 0,
				delta: { type: 'signature_delta', signature: 'c2lnbmF0dXJl' },
			},
		],
		['content_block_stop', { type: 'content_block_stop', index: 0 }],
		[
			'content_block_start',
			{
				type: 'content_block_start',
				index: 1,
				content_block: { type: 'text', text: '' },
			},
		],
		[
			'content_block_delta',
			{
				type: 'content_block_delta',
				index: 1,
				delta: { type: 'text_delta', text: reply.text },
			},
		],
		['content_block_stop', { type: 'content_block_stop', index: 1 }],
		[
			'message_delta',
			{
				type: 'message_delta',
				delta: { stop_reason: 'end_turn', stop_sequence: null },
				usage: { output_tokens: 80 },
			},
		],
		['message_stop', { type: 'message_stop' }],
	];
	return events
		.map(([name, data]) => `event: ${name}\ndata: ${JSON.stringify(data)}\n\n`)
		.join('');
}

const failures = [];
const check = (ok, what) => {
	console.log(`  ${ok ? 'ok  ' : 'FAIL'} ${what}`);
	if (!ok) failures.push(what);
};

async function runOnce(browser, name, viewport, { watchAgent }) {
	console.log(`\n${name} (${viewport.width}x${viewport.height})`);
	const context = await browser.newContext({ viewport });
	await context.addInitScript(() => {
		localStorage.setItem(
			'henryos.session',
			JSON.stringify({
				access_token: 't',
				refresh_token: 'r',
				expires_at: Date.now() + 3600000,
				email: 'smoke@example.com',
				user_id: 'u',
			}),
		);
		localStorage.setItem('godmode.key.anthropic', 'sk-ant-smoke-test');
	});
	const page = await context.newPage();
	const problems = [];
	const requests = [];
	page.on('console', (m) => {
		if (m.type() === 'error' || m.type() === 'warning')
			problems.push(`${m.type()}: ${m.text()}`);
	});
	page.on('pageerror', (e) => problems.push('pageerror: ' + e.message));

	await page.route('https://api.anthropic.com/**', async (route) => {
		const request = route.request();
		if (request.method() === 'OPTIONS')
			return route.fulfill({ status: 204, headers: CORS });
		const body = request.postDataJSON();
		const role = Object.keys(REPLIES).find((r) =>
			body.system.includes(`You are the ${r}.`),
		);
		requests.push({ role, body, headers: request.headers() });
		// hold the specialists briefly so the "working" state can be seen
		if (role === 'Researcher' || role === 'Analyst')
			await new Promise((r) => setTimeout(r, 1500));
		return route.fulfill({
			status: 200,
			headers: { ...CORS, 'content-type': 'text/event-stream' },
			body: sse(body.model, REPLIES[role]),
		});
	});

	await page.goto(`${BASE}/world.html`);
	await page.waitForSelector('#roster [data-agent="planner"]');
	check(
		(await page.locator('#roster [data-agent]').count()) === 6,
		'six agents are listed',
	);
	check(
		await page.locator('#nokey').isHidden(),
		'no key prompt when a key is saved',
	);
	const shot = async (label) => {
		if (!SHOTS) return;
		fs.mkdirSync(SHOTS, { recursive: true });
		await page.screenshot({ path: path.join(SHOTS, `${name}-${label}.png`) });
	};
	await page.waitForTimeout(600);
	await shot('1-idle');

	await page.fill('#mission', 'Plan a launch for my small app');
	await page.click('#run');
	await page.waitForFunction(
		() =>
			document.querySelector('#roster [data-agent="researcher"]')?.dataset
				.state === 'thinking',
	);
	check(
		(await page
			.locator('#roster [data-agent="engineer"]')
			.getAttribute('data-state')) === 'skipped',
		'the unassigned Engineer sits the mission out',
	);
	if (watchAgent) {
		await page.click('#roster [data-agent="researcher"]');
		await page.waitForSelector('#panel:not([hidden])');
		check(
			(await page.locator('#panelName').innerText()) === 'Researcher',
			'tapping an agent opens its panel',
		);
		// watch the labels for the whole camera move towards the building, not one instant of it
		const clash = await page.evaluate(async () => {
			const floor = document
				.querySelector('#steps')
				.getBoundingClientRect().bottom;
			const seen = new Set();
			for (let i = 0; i < 12; i++) {
				for (const l of document.querySelectorAll('#labels .label')) {
					if (
						l.style.visibility !== 'hidden' &&
						l.getBoundingClientRect().top < floor
					)
						seen.add(l.textContent);
				}
				await new Promise((r) => setTimeout(r, 80));
			}
			return [...seen];
		});
		check(
			clash.length === 0,
			`no building label sits under the top bar${clash.length ? ' (' + clash.join(', ') + ')' : ''}`,
		);
		await shot('2-working');
		await page.waitForFunction(
			() => document.querySelector('#phase').textContent === 'Delivered',
			null,
			{ timeout: 20000 },
		);
		check(
			await page.locator('#panel').isVisible(),
			'finishing does not pull you away from the agent you are reading',
		);
		check(
			await page.locator('#resultBtn.fresh').isVisible(),
			'the result button shows there is something new',
		);
		await page.click('#resultBtn');
	} else {
		await page.waitForTimeout(500);
		await shot('2-working');
	}
	await page.waitForSelector('#result:not([hidden])', { timeout: 20000 });
	check(
		true,
		watchAgent
			? 'the result opens from its button'
			: 'the result opens by itself when nothing else is open',
	);
	const resultText = await page.locator('#resultBody').innerText();
	check(/Launch plan/.test(resultText), 'the deliverable is shown');
	check(
		(await page.locator('#resultBody table').count()) === 1,
		'markdown tables render',
	);
	check(
		(await page.evaluate(() => window.pwned)) === undefined,
		'HTML in agent output is not executed',
	);
	check(
		/tokens/.test(await page.locator('#resultMeta').innerText()),
		'token use is reported',
	);
	await page.waitForTimeout(400);
	await shot('3-result');

	await page.click('#resultClose');
	await page.click('#roster [data-agent="researcher"]');
	await page.click('#panel [data-tab="thoughts"]');
	check(
		/comparable launches before drawing/.test(
			await page.locator('#panelBody').innerText(),
		),
		'an agent’s reasoning is readable afterwards',
	);
	await page.click('#panel [data-tab="work"]');
	check(
		/Launch A grew by referral/.test(
			await page.locator('#panelBody').innerText(),
		),
		'an agent’s work is readable afterwards',
	);
	await page.click('#panel [data-tab="brief"]');
	check(
		/Find three comparable launches/.test(
			await page.locator('#panelBody').innerText(),
		),
		'an agent’s brief is readable afterwards',
	);
	await page.waitForTimeout(300);
	await shot('4-agent');

	const roles = requests.map((r) => r.role);
	check(
		JSON.stringify([...roles].sort()) ===
			JSON.stringify(['Analyst', 'Critic', 'Planner', 'Researcher', 'Writer']),
		`five agents were called (${roles.join(', ')})`,
	);
	const first = requests[0];
	// current SDK releases send an API key as a Bearer token rather than x-api-key
	check(
		first.headers.authorization === 'Bearer sk-ant-smoke-test',
		'the saved key is sent to Anthropic',
	);
	check(
		first.headers['anthropic-dangerous-direct-browser-access'] === 'true',
		'the browser-access header is sent',
	);
	check(
		first.body.thinking?.display === 'summarized',
		'reasoning summaries are requested',
	);
	check(first.body.stream === true, 'responses are streamed');
	check(
		requests.find((r) => r.role === 'Researcher').body.tools?.[0]?.type ===
			'web_search_20260209',
		'the Researcher has web search',
	);

	// a reload keeps the finished mission
	await page.reload();
	const kept = await page
		.waitForSelector('#roster [data-agent="writer"][data-state="done"]', {
			timeout: 10000,
		})
		.then(
			() => true,
			() => false,
		);
	check(kept, 'a reload keeps the last mission');
	await page.click('#resultBtn');
	check(
		/Launch plan/.test(await page.locator('#resultBody').innerText()),
		'the last result can be reopened',
	);

	check(
		problems.length === 0,
		`no console errors or warnings${problems.length ? ': ' + problems.join(' | ') : ''}`,
	);
	await context.close();
}

async function noKey(browser) {
	console.log('\nno key saved');
	const context = await browser.newContext({
		viewport: { width: 390, height: 844 },
	});
	await context.addInitScript(() => {
		localStorage.setItem(
			'henryos.session',
			JSON.stringify({
				access_token: 't',
				refresh_token: 'r',
				expires_at: Date.now() + 3600000,
				email: 'smoke@example.com',
				user_id: 'u',
			}),
		);
	});
	const page = await context.newPage();
	await page.goto(`${BASE}/world.html`);
	await page.waitForSelector('#nokey:not([hidden])');
	check(
		(await page.locator('#nokey a').getAttribute('href')) === 'index.html#keys',
		'without a key, the page points to Henry OS settings',
	);
	if (SHOTS)
		await page.screenshot({ path: path.join(SHOTS, 'phone-0-nokey.png') });
	await context.close();

	const signedOut = await browser.newContext();
	const page2 = await signedOut.newPage();
	await page2.goto(`${BASE}/world.html`);
	await page2.waitForURL(/index\.html$/);
	check(true, 'signed out, the page sends you to the Henry OS sign-in');
	await signedOut.close();
}

(async () => {
	const server = spawn(
		process.execPath,
		[path.join(__dirname, '..', '..', 'scripts', 'scripts', 'serve-web.js')],
		{
			env: { ...process.env, PORT },
			stdio: 'ignore',
		},
	);
	let browser;
	try {
		await new Promise((r) => setTimeout(r, 700));
		browser = await chromium.launch({
			args: [
				'--use-angle=swiftshader',
				'--enable-unsafe-swiftshader',
				'--ignore-gpu-blocklist',
			],
		});
		await runOnce(
			browser,
			'phone',
			{ width: 390, height: 844 },
			{ watchAgent: true },
		);
		await runOnce(
			browser,
			'desktop',
			{ width: 1280, height: 800 },
			{ watchAgent: false },
		);
		await noKey(browser);
	} catch (err) {
		failures.push('smoke run crashed: ' + err.message);
		console.error(err);
	} finally {
		if (browser) await browser.close();
		server.kill();
	}
	console.log(
		failures.length
			? `\n${failures.length} check(s) failed`
			: '\nAll checks passed',
	);
	process.exit(failures.length ? 1 : 0);
})();
