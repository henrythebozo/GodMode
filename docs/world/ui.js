/**
 * The HUD over the town: the roster, the labels pinned to buildings, the
 * agent sheet (Thoughts / Work / Brief), the result sheet, the composer and
 * the settings dialog.
 *
 * It holds what each agent has said so far and draws it; it decides nothing
 * about the mission. main.js feeds it events and listens to `handlers`:
 *   onStart(goal)  onStop()  onSelect(id | null)  onSettings({ model, webSearch })
 */
import { renderMarkdown } from './markdown.js';
import {
	MODELS,
	modelById,
	mergeUsage,
	estimateCost,
	formatCost,
	formatTokens,
} from './models.js';

const STATE_WORDS = {
	idle: 'Idle',
	queued: 'Waiting',
	thinking: 'Thinking',
	writing: 'Writing',
	done: 'Done',
	skipped: 'Sitting out',
	error: 'Failed',
};

const PHASE_WORDS = {
	ready: 'Ready',
	plan: 'Planning',
	work: 'Specialists at work',
	write: 'Writing it up',
	review: 'Under review',
	revise: 'Revising',
	done: 'Delivered',
	stopped: 'Stopped',
	failed: 'Failed',
};

// which of the four drawn steps a phase belongs to; 4 means all finished
const STEP_OF = { plan: 0, work: 1, write: 2, review: 3, revise: 3, done: 4 };

const SUGGESTIONS = [
	'Plan a weekend launch for a small iPhone app',
	'Compare three ways to learn Spanish in three months',
	'Design a simple backup routine for my family photos',
];

// Reasoning kept per agent when a mission is saved, in characters.
const SAVED_FEED = 8000;

const NO_USAGE = { input: 0, output: 0, searches: 0 };

const blank = () => ({
	state: 'idle',
	brief: '',
	feed: [],
	text: '',
	output: null,
	usage: NO_USAGE,
});

const el = (tag, className, text) => {
	const node = document.createElement(tag);
	if (className) node.className = className;
	if (text != null) node.textContent = text;
	return node;
};

const tail = (text, length) => {
	const flat = text.replace(/\s+/g, ' ').trim();
	return flat.length > length ? '…' + flat.slice(-length) : flat;
};

export function createHud(roster, handlers) {
	const $ = (id) => document.getElementById(id);
	const form = $('missionForm');
	const missionEl = $('mission');
	const runBtn = $('run');
	const statusEl = $('status');
	const rosterEl = $('roster');
	const labelsEl = $('labels');
	const suggestEl = $('suggest');
	const stepsEl = $('steps');
	const panel = $('panel');
	const panelBody = $('panelBody');
	const result = $('result');
	const settings = $('settings');

	const agents = new Map(roster.map((info) => [info.id, { info, ...blank() }]));
	const chips = new Map();
	const labels = new Map();
	let selected = null;
	let tab = 'thoughts';
	let running = false;
	let lastResult = null;
	let drawQueued = false;
	// how much of the top and bottom of the screen the HUD covers, as last measured by insets()
	let covered = { top: 0, bottom: 0 };

	/* ------------------------------ roster ----------------------------- */
	for (const info of roster) {
		const chip = el('button', 'agent');
		chip.type = 'button';
		chip.dataset.agent = info.id;
		chip.dataset.state = 'idle';
		chip.style.setProperty('--c', info.color);
		chip.title = `${info.place}. ${info.job}`;
		const text = el('span', 'text');
		text.append(el('b', '', info.name), el('span', '', STATE_WORDS.idle));
		chip.append(el('i', 'dot'), text);
		chip.addEventListener('click', () =>
			selected === info.id ? close() : open(info.id),
		);
		rosterEl.append(chip);
		chips.set(info.id, chip);

		const label = el('button', 'label');
		label.type = 'button';
		label.dataset.state = 'idle';
		label.style.setProperty('--c', info.color);
		label.setAttribute('aria-label', `${info.name}, ${info.place}`);
		label.append(el('i', 'dot'), el('b', '', info.name), el('span', 'thought'));
		label.addEventListener('click', () => open(info.id));
		label.style.visibility = 'hidden'; // until the town says where its building is
		labelsEl.append(label);
		labels.set(info.id, label);
	}

	/* ----------------------------- composer ---------------------------- */
	for (const idea of SUGGESTIONS) {
		const b = el('button', '', idea);
		b.type = 'button';
		// fills the box rather than starting: a mission costs money, so starting is always a deliberate tap
		b.addEventListener('click', () => {
			missionEl.value = idea;
			autosize();
			missionEl.focus();
		});
		suggestEl.append(b);
	}

	function autosize() {
		missionEl.style.height = 'auto';
		missionEl.style.height = Math.min(missionEl.scrollHeight, 130) + 'px';
		suggestEl.hidden =
			running || Boolean(missionEl.value.trim()) || Boolean(lastResult);
	}
	missionEl.addEventListener('input', autosize);
	missionEl.addEventListener('keydown', (e) => {
		if (
			e.key === 'Enter' &&
			!e.shiftKey &&
			!e.isComposing &&
			handlers.enterSends()
		) {
			e.preventDefault();
			form.requestSubmit();
		}
	});
	form.addEventListener('submit', (e) => {
		e.preventDefault();
		if (running) return handlers.onStop();
		const goal = missionEl.value.trim();
		if (goal) handlers.onStart(goal);
	});

	/* ---------------------------- agent sheet -------------------------- */
	function emptyMessage(agent, forTab) {
		const { name } = agent.info;
		if (agent.state === 'skipped')
			return `The Planner did not need the ${name} for this mission.`;
		if (agent.state === 'idle') return 'No mission yet.';
		if (agent.state === 'queued') return 'Waiting for its turn.';
		if (forTab === 'brief') return 'No brief yet.';
		if (forTab === 'work')
			return agent.state === 'error'
				? 'This step failed before anything was written.'
				: 'Nothing written yet.';
		if (agent.state === 'thinking') return 'Thinking.';
		return 'No reasoning was reported for this step.';
	}

	function drawBody(agent) {
		panelBody.replaceChildren();
		if (tab === 'thoughts' && agent.feed.length) {
			for (const item of agent.feed) {
				if (item.kind === 'think')
					panelBody.append(el('p', 'think', item.text));
				else if (item.kind === 'tool')
					panelBody.append(
						el('p', 'event', `Searched the web for “${item.text}”`),
					);
				else panelBody.append(el('p', 'event warn', item.text));
			}
			return;
		}
		const source =
			tab === 'work'
				? (agent.output ?? agent.text)
				: tab === 'brief'
					? agent.brief
					: '';
		if (source) {
			const md = el('div', 'md');
			// renderMarkdown escapes its input before adding any tags of its own
			md.innerHTML = renderMarkdown(source);
			panelBody.append(md);
			return;
		}
		panelBody.append(el('p', 'empty', emptyMessage(agent, tab)));
	}

	function drawPanel({ jump = false } = {}) {
		if (!selected) return;
		const agent = agents.get(selected);
		const live = agent.state === 'thinking' || agent.state === 'writing';
		const nearEnd =
			panelBody.scrollHeight - panelBody.scrollTop - panelBody.clientHeight <
			60;
		panel.style.setProperty('--c', agent.info.color);
		panel.querySelector('header').dataset.state = agent.state;
		$('panelName').textContent = agent.info.name;
		$('panelPlace').textContent = `${agent.info.place}. ${agent.info.job}`;
		$('panelState').textContent = STATE_WORDS[agent.state];
		for (const b of panel.querySelectorAll('[data-tab]')) {
			b.classList.toggle('on', b.dataset.tab === tab);
			b.setAttribute('aria-selected', String(b.dataset.tab === tab));
		}
		drawBody(agent);
		const tokens = agent.usage.input + agent.usage.output;
		const searches = agent.usage.searches;
		$('panelUsage').textContent = tokens
			? `${formatTokens(tokens)} tokens` +
				(searches
					? `, ${searches} web search${searches === 1 ? '' : 'es'}`
					: '')
			: '';
		// follow the stream only while the reader is already at the end of it
		if (jump) panelBody.scrollTop = live ? panelBody.scrollHeight : 0;
		else if (live && nearEnd) panelBody.scrollTop = panelBody.scrollHeight;
	}

	function drawThought(id) {
		const agent = agents.get(id);
		const lastThink =
			agent.feed.findLast?.((f) => f.kind === 'think')?.text || '';
		const line =
			agent.state === 'writing' && agent.text ? agent.text : lastThink;
		labels.get(id).querySelector('.thought').textContent = tail(line, 44);
	}

	// streamed deltas arrive far faster than the screen refreshes: draw once a frame
	const dirty = new Set();
	function touch(id) {
		dirty.add(id);
		if (drawQueued) return;
		drawQueued = true;
		requestAnimationFrame(() => {
			drawQueued = false;
			for (const each of dirty) drawThought(each);
			if (dirty.has(selected)) drawPanel();
			dirty.clear();
		});
	}

	function setSheet(which) {
		panel.hidden = which !== 'panel';
		result.hidden = which !== 'result';
		document.body.classList.toggle('sheet-open', Boolean(which));
	}

	function open(id) {
		const agent = agents.get(id);
		if (!agent) return;
		selected = id;
		tab =
			agent.state === 'thinking' || (!agent.output && !agent.text)
				? 'thoughts'
				: 'work';
		for (const [each, chip] of chips) chip.classList.toggle('on', each === id);
		setSheet('panel');
		drawPanel({ jump: true });
		handlers.onSelect(id);
	}

	function close() {
		selected = null;
		for (const chip of chips.values()) chip.classList.remove('on');
		setSheet(null);
		handlers.onSelect(null);
	}

	$('panelClose').addEventListener('click', close);
	for (const b of panel.querySelectorAll('[data-tab]')) {
		b.addEventListener('click', () => {
			tab = b.dataset.tab;
			drawPanel({ jump: true });
		});
	}

	/* ---------------------------- result sheet ------------------------- */
	function drawResult() {
		const { markdown, model, usage, notes } = lastResult;
		const cost = formatCost(estimateCost(usage, model));
		$('resultMeta').textContent =
			`${modelById(model).label}, ${formatTokens(usage.input + usage.output)} tokens, about ${cost}`;
		const notesEl = $('resultNotes');
		notesEl.replaceChildren(...notes.map((n) => el('li', '', n)));
		notesEl.hidden = !notes.length;
		// renderMarkdown escapes its input before adding any tags of its own
		$('resultBody').innerHTML = renderMarkdown(markdown);
		$('resultBody').scrollTop = 0;
	}

	function openResult() {
		if (!lastResult) return;
		selected = null;
		for (const chip of chips.values()) chip.classList.remove('on');
		drawResult();
		setSheet('result');
		$('resultBtn').classList.remove('fresh');
		handlers.onSelect(null);
	}

	$('resultBtn').addEventListener('click', () =>
		result.hidden ? openResult() : close(),
	);
	$('resultClose').addEventListener('click', close);
	$('copyBtn').addEventListener('click', async () => {
		const button = $('copyBtn');
		try {
			await navigator.clipboard.writeText(lastResult.markdown);
			button.textContent = 'Copied';
		} catch {
			button.textContent = 'Copy failed';
		}
		setTimeout(() => (button.textContent = 'Copy'), 1600);
	});
	$('downloadBtn').addEventListener('click', () => {
		const url = URL.createObjectURL(
			new Blob([lastResult.markdown], { type: 'text/markdown' }),
		);
		const link = el('a');
		link.href = url;
		link.download = 'mission.md';
		link.click();
		setTimeout(() => URL.revokeObjectURL(url), 1000);
	});

	/* ------------------------------ settings --------------------------- */
	for (const model of MODELS) {
		const row = el('label', 'model');
		const input = el('input');
		input.type = 'radio';
		input.name = 'model';
		input.value = model.id;
		const text = el('span', 'text');
		text.append(el('b', '', model.label), el('span', '', model.note));
		row.append(input, text);
		$('modelList').append(row);
	}
	const settingsNow = () => ({
		model: settings.querySelector('input[name="model"]:checked')?.value,
		webSearch: $('webSearch').checked,
	});
	settings.addEventListener('change', () => handlers.onSettings(settingsNow()));
	$('settingsBtn').addEventListener('click', () => settings.showModal());
	$('settingsDone').addEventListener('click', () => settings.close());

	window.addEventListener('keydown', (e) => {
		if (e.key === 'Escape' && !settings.open && (selected || !result.hidden))
			close();
	});

	autosize();

	/* ----------------------------- public API -------------------------- */
	return {
		open,
		close,
		openResult,
		stateOf: (id) => agents.get(id)?.state,

		setSettings({ model, webSearch }) {
			const radio = settings.querySelector(
				`input[name="model"][value="${model}"]`,
			);
			if (radio) radio.checked = true;
			$('webSearch').checked = webSearch;
		},

		showNoKey(show) {
			$('nokey').hidden = !show;
			runBtn.disabled = show;
			missionEl.disabled = show || running;
		},

		setRunning(on) {
			running = on;
			runBtn.classList.toggle('stop', on);
			const label = on ? 'Stop the mission' : 'Start the mission';
			runBtn.title = label;
			runBtn.setAttribute('aria-label', label);
			missionEl.disabled = on;
			stepsEl.classList.toggle('on', on || Boolean(lastResult));
			autosize();
		},

		setMission(goal) {
			missionEl.value = goal;
			autosize();
		},

		setPhase(phase) {
			$('phase').textContent = PHASE_WORDS[phase] || PHASE_WORDS.ready;
			const at = STEP_OF[phase];
			if (at === undefined) return; // stopped or failed: leave the track where it got to
			[...stepsEl.children].forEach((li, i) => {
				li.classList.toggle('done', i < at);
				li.classList.toggle('now', i === at);
			});
		},

		setStatus(text, isError = false) {
			statusEl.textContent = text;
			statusEl.classList.toggle('err', isError);
		},

		reset() {
			for (const [id, agent] of agents) {
				Object.assign(agent, blank());
				this.setState(id, 'idle');
				drawThought(id);
			}
			lastResult = null;
			$('resultBtn').hidden = true;
			$('resultBtn').classList.remove('fresh');
			if (!result.hidden) setSheet(null);
			for (const li of stepsEl.children) li.classList.remove('done', 'now');
		},

		setState(id, state) {
			const agent = agents.get(id);
			if (!agent) return;
			agent.state = state;
			const chip = chips.get(id);
			chip.dataset.state = state;
			chip.querySelector('.text span').textContent = STATE_WORDS[state];
			labels.get(id).dataset.state = state;
			touch(id);
		},

		setBrief(id, text) {
			const agent = agents.get(id);
			if (!agent) return;
			agent.brief = text;
			touch(id);
		},

		addThinking(id, delta) {
			const agent = agents.get(id);
			if (!agent) return;
			const last = agent.feed.at(-1);
			if (last?.kind === 'think') last.text += delta;
			else agent.feed.push({ kind: 'think', text: delta });
			touch(id);
		},

		addText(id, delta) {
			const agent = agents.get(id);
			if (!agent) return;
			agent.text += delta;
			touch(id);
		},

		addTool(id, query) {
			agents.get(id)?.feed.push({ kind: 'tool', text: query });
			touch(id);
		},

		addNote(id, text) {
			agents.get(id)?.feed.push({ kind: 'note', text });
			touch(id);
		},

		setOutput(id, markdown) {
			const agent = agents.get(id);
			if (!agent) return;
			agent.output = markdown;
			touch(id);
		},

		/** The agent is starting over: clear what it wrote, keep what it thought. */
		restart(id) {
			const agent = agents.get(id);
			if (!agent) return;
			agent.text = '';
			agent.output = null;
			touch(id);
		},

		addUsage(id, usage) {
			const agent = agents.get(id);
			if (!agent) return;
			agent.usage = mergeUsage(agent.usage, usage);
			touch(id);
		},

		/**
		 * Returns whether the result was opened. It is not when the person is
		 * reading an agent's sheet: finishing should not pull that away, so the
		 * result button is marked as having something new instead.
		 */
		setResult(found, { show = true } = {}) {
			lastResult = found;
			$('resultBtn').hidden = false;
			stepsEl.classList.add('on');
			autosize();
			if (show && !selected) {
				openResult();
				return true;
			}
			$('resultBtn').classList.toggle('fresh', show);
			return false;
		},

		/** Pin each label above its building. Called once per rendered frame. */
		placeLabels(anchor) {
			for (const [id, label] of labels) {
				const at = anchor(id);
				// a label that would slide under the top bar or the dock is hidden instead
				const clear =
					at &&
					at.visible &&
					at.y - label.offsetHeight >= covered.top &&
					at.y <= innerHeight - covered.bottom;
				if (!clear) {
					label.style.visibility = 'hidden';
					continue;
				}
				label.style.visibility = '';
				label.style.transform = `translate(${at.x.toFixed(1)}px, ${at.y.toFixed(1)}px) translate(-50%, -100%)`;
			}
		},

		/** How much of each edge of the screen the HUD covers, for framing the town. */
		insets() {
			const top = stepsEl.getBoundingClientRect().bottom;
			const sheet = !panel.hidden ? panel : !result.hidden ? result : null;
			const wide = matchMedia('(min-width: 900px)').matches;
			const bottom =
				innerHeight -
				(sheet && !wide ? sheet : rosterEl).getBoundingClientRect().top;
			const right =
				sheet && wide ? innerWidth - sheet.getBoundingClientRect().left : 0;
			covered = { top, bottom };
			return { top, right, bottom, left: 0 };
		},

		/** Everything needed to show this mission again after a reload. */
		snapshot() {
			const saved = {};
			for (const [id, agent] of agents) {
				let room = SAVED_FEED;
				const feed = [];
				for (const item of [...agent.feed].reverse()) {
					if (room <= 0) break;
					feed.unshift({ kind: item.kind, text: item.text.slice(-room) });
					room -= item.text.length;
				}
				saved[id] = {
					state: agent.state,
					brief: agent.brief,
					feed,
					output: agent.output ?? agent.text,
					usage: agent.usage,
				};
			}
			return saved;
		},

		restore(saved) {
			for (const [id, agent] of agents) {
				const from = saved?.[id];
				if (!from) continue;
				Object.assign(agent, blank(), {
					brief: from.brief || '',
					feed: Array.isArray(from.feed) ? from.feed : [],
					output: from.output || null,
					usage: from.usage || NO_USAGE,
				});
				// nothing is running after a reload, whatever was mid-flight when it was saved
				const settled = ['done', 'skipped', 'error'].includes(from.state)
					? from.state
					: 'idle';
				this.setState(id, settled);
			}
		},
	};
}
