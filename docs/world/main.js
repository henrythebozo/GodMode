/**
 * Wires the World page together: the saved key and settings (store), the HUD
 * (ui), the 3D town (scene) and the mission engine (mission). Mission events
 * come in here and are fanned out to the HUD and the town.
 */
import Anthropic from '../vendor/anthropic-sdk.min.js';
import { ROSTER, PLAZA } from './roster.js';
import { store } from './store.js';
import { createHud } from './ui.js';
import { runMission } from './mission.js';
import { formatTokens } from './models.js';

if (!store.signedIn) location.replace('index.html');

/** Stands in for the town when 3D cannot start, so missions still run. */
const NO_TOWN = {
	setState() {},
	sendCourier: async () => {},
	setBeacon() {},
	focus() {},
	setInsets() {},
	onPick() {},
	onFrame() {},
	anchor: () => null,
};

async function loadTown(canvas) {
	try {
		const { createWorld } = await import('./scene.js');
		return createWorld(canvas, ROSTER);
	} catch (err) {
		// no WebGL, or a browser too old for the 3D library
		console.info('The 3D town could not start:', err);
		canvas.hidden = true;
		return null;
	}
}

// The HUD is usable while the 3D library is still loading, so the town starts
// as the stand-in and is swapped for the real one when it is ready.
let town = NO_TOWN;
let beacon = 'idle';
let controller = null;
let timer = null;
let tokens = 0;

function setBeacon(mode) {
	beacon = mode;
	town.setBeacon(mode);
}

const hud = createHud(ROSTER, {
	onStart: start,
	onStop: () => controller?.abort(),
	onSelect: (id) => {
		town.setInsets(hud.insets());
		town.focus(id);
	},
	onSettings: ({ model, webSearch }) => {
		if (model) store.model = model;
		store.webSearch = webSearch;
	},
	enterSends: () => store.enterSends,
});
hud.setSettings({ model: store.model, webSearch: store.webSearch });

const refreshKey = () => hud.showNoKey(!store.anthropicKey);
refreshKey();
// the key is added in Henry OS settings; pick it up on the way back
window.addEventListener('pageshow', refreshKey);
window.addEventListener('focus', refreshKey);

// bring back the last finished mission, so a reload does not lose paid-for work
const last = store.lastMission;
if (last?.result?.markdown && last.agents) {
	hud.restore(last.agents);
	hud.setMission(last.goal || '');
	hud.setPhase('done');
	hud.setResult({ ...last.result, model: last.model }, { show: false });
	beacon = 'done';
}

town = (await loadTown(document.getElementById('town'))) || NO_TOWN;
if (town === NO_TOWN) {
	hud.setStatus(
		'3D is not available in this browser. Missions still run; tap an agent to follow it.',
	);
}
// whatever happened while it loaded, the town now shows the same as the HUD
for (const { id } of ROSTER) town.setState(id, hud.stateOf(id));
town.setBeacon(beacon);
town.setInsets(hud.insets());
town.onFrame(() => hud.placeLabels(town.anchor));
town.onPick((id) => (id === PLAZA ? hud.openResult() : hud.open(id)));
window.addEventListener('resize', () => town.setInsets(hud.insets()));

function setAgentState(id, state) {
	hud.setState(id, state);
	town.setState(id, state);
}

function onEvent(event) {
	switch (event.type) {
		case 'phase':
			hud.setPhase(event.phase);
			break;
		case 'state':
			setAgentState(event.id, event.state);
			break;
		case 'brief':
			hud.setBrief(event.id, event.text);
			break;
		case 'thinking':
			hud.addThinking(event.id, event.delta);
			break;
		case 'text':
			hud.addText(event.id, event.delta);
			break;
		case 'tool':
			hud.addTool(event.id, event.query);
			break;
		case 'note':
			if (event.id) hud.addNote(event.id, event.text);
			break;
		case 'restart':
			hud.restart(event.id);
			break;
		case 'output':
			hud.setOutput(event.id, event.markdown);
			break;
		case 'usage':
			hud.addUsage(event.id, event.usage);
			tokens += event.usage.input + event.usage.output;
			break;
		case 'handoff':
			town.sendCourier(event.from, event.to);
			break;
	}
}

function showElapsed(since) {
	const s = Math.floor((Date.now() - since) / 1000);
	const clock = `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`;
	hud.setStatus(
		tokens
			? `${clock} elapsed, ${formatTokens(tokens)} tokens so far`
			: `${clock} elapsed`,
	);
}

/** Agents caught mid-step when a mission ends early go back to idle. */
function settleAgents() {
	for (const { id } of ROSTER) {
		if (['queued', 'thinking', 'writing'].includes(hud.stateOf(id)))
			setAgentState(id, 'idle');
	}
}

async function start(goal) {
	const apiKey = store.anthropicKey;
	if (!apiKey) return refreshKey();
	const model = store.model;

	// The key is the person's own, already kept in this browser by Henry OS,
	// and goes straight to Anthropic — the same direct call index.html makes.
	const client = new Anthropic({
		apiKey,
		dangerouslyAllowBrowser: true,
		maxRetries: 3,
	});

	controller = new AbortController();
	tokens = 0;
	hud.close();
	hud.reset();
	for (const { id } of ROSTER) town.setState(id, 'idle');
	setBeacon('running');
	hud.setRunning(true);
	const since = Date.now();
	showElapsed(since);
	timer = setInterval(() => showElapsed(since), 1000);

	const outcome = await runMission({
		goal,
		client,
		model,
		emit: onEvent,
		signal: controller.signal,
		today: new Date().toDateString(),
		webSearch: store.webSearch,
	});

	clearInterval(timer);
	controller = null;
	hud.setRunning(false);

	if (outcome.status === 'done') {
		const result = {
			markdown: outcome.result,
			usage: outcome.usage,
			notes: [
				...(outcome.revised ? ['Revised once after the Critic’s review.'] : []),
				...outcome.notes,
			],
		};
		setBeacon('done');
		const opened = hud.setResult({ ...result, model });
		hud.setStatus(opened ? '' : 'Delivered. Open the result from the top bar.');
		store.lastMission = { goal, model, result, agents: hud.snapshot() };
		return;
	}
	settleAgents();
	if (outcome.status === 'stopped') {
		setBeacon('idle');
		hud.setStatus('Stopped. Nothing after this point was run.');
	} else {
		setBeacon('error');
		hud.setStatus(outcome.message, true);
	}
}
