// GodMode Screen Answers — background service worker
//
// Flow: user hits the keyboard shortcut (or the popup button) -> we screenshot
// the visible tab -> send it to Claude with a question -> show the answer in
// an overlay injected into the page by content.js. Everything (API key,
// model, default prompt) lives in chrome.storage.local; nothing leaves the
// browser except the request straight to api.anthropic.com.

const ANTHROPIC_API_URL = "https://api.anthropic.com/v1/messages";
const DEFAULT_MODEL = "claude-sonnet-5";
const DEFAULT_PROMPT =
	"Answer the question shown in this screenshot. If there's no explicit question, briefly explain what's on screen.";

// Per-tab conversation state so follow-up questions keep context without
// re-sending the (often large) screenshot every time.
const sessions = new Map(); // tabId -> { messages: [...] }

async function getSettings() {
	const { apiKey, model, defaultPrompt } = await chrome.storage.local.get([
		"apiKey",
		"model",
		"defaultPrompt",
	]);
	return {
		apiKey: apiKey || "",
		model: model || DEFAULT_MODEL,
		defaultPrompt: defaultPrompt || DEFAULT_PROMPT,
	};
}

async function askClaude(messages, { apiKey, model }) {
	const res = await fetch(ANTHROPIC_API_URL, {
		method: "POST",
		headers: {
			"content-type": "application/json",
			"x-api-key": apiKey,
			"anthropic-version": "2023-06-01",
			// Required for calling the Messages API directly from a browser.
			"anthropic-dangerous-direct-browser-access": "true",
		},
		body: JSON.stringify({
			model,
			max_tokens: 1024,
			messages,
		}),
	});

	if (!res.ok) {
		let detail = "";
		try {
			const body = await res.json();
			detail = body?.error?.message || JSON.stringify(body);
		} catch {
			detail = await res.text();
		}
		throw new Error(`Claude API error (${res.status}): ${detail}`);
	}

	const data = await res.json();
	return (data.content || [])
		.filter((block) => block.type === "text")
		.map((block) => block.text)
		.join("\n")
		.trim();
}

async function sendToTab(tabId, message) {
	try {
		await chrome.tabs.sendMessage(tabId, message);
	} catch (err) {
		// Content script may not be injected yet (e.g. chrome:// pages) — nothing
		// useful we can do about that here.
		console.warn("GodMode: could not reach content script", err);
	}
}

async function runCapture(tab, question) {
	if (!tab || !tab.id || !tab.windowId) return;

	const settings = await getSettings();
	if (!settings.apiKey) {
		await sendToTab(tab.id, {
			type: "GODMODE_SHOW_ERROR",
			error: "No Anthropic API key set yet. Click the extension icon → Options to add one.",
		});
		chrome.runtime.openOptionsPage();
		return;
	}

	let screenshot;
	try {
		screenshot = await chrome.tabs.captureVisibleTab(tab.windowId, {
			format: "png",
		});
	} catch (err) {
		await sendToTab(tab.id, {
			type: "GODMODE_SHOW_ERROR",
			error: `Couldn't capture the screen: ${err.message}`,
		});
		return;
	}

	await sendToTab(tab.id, { type: "GODMODE_SHOW_LOADING", screenshot });

	const base64 = screenshot.split(",")[1];
	const prompt = (question && question.trim()) || settings.defaultPrompt;

	const messages = [
		{
			role: "user",
			content: [
				{
					type: "image",
					source: { type: "base64", media_type: "image/png", data: base64 },
				},
				{ type: "text", text: prompt },
			],
		},
	];

	sessions.set(tab.id, { messages });

	try {
		const answer = await askClaude(messages, settings);
		sessions.get(tab.id).messages.push({ role: "assistant", content: answer });
		await sendToTab(tab.id, { type: "GODMODE_SHOW_ANSWER", answer });
	} catch (err) {
		await sendToTab(tab.id, {
			type: "GODMODE_SHOW_ERROR",
			error: err.message,
		});
	}
}

async function runFollowup(tabId, question) {
	const session = sessions.get(tabId);
	if (!session) {
		await sendToTab(tabId, {
			type: "GODMODE_SHOW_ERROR",
			error: "No active screenshot to ask about — capture one first.",
		});
		return;
	}

	const settings = await getSettings();
	session.messages.push({ role: "user", content: question });
	await sendToTab(tabId, { type: "GODMODE_SHOW_LOADING" });

	try {
		const answer = await askClaude(session.messages, settings);
		session.messages.push({ role: "assistant", content: answer });
		await sendToTab(tabId, { type: "GODMODE_SHOW_ANSWER", answer });
	} catch (err) {
		await sendToTab(tabId, {
			type: "GODMODE_SHOW_ERROR",
			error: err.message,
		});
	}
}

chrome.commands.onCommand.addListener(async (command) => {
	if (command !== "capture-and-ask") return;
	const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
	runCapture(tab);
});

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
	if (message.type === "GODMODE_TRIGGER_CAPTURE") {
		(async () => {
			const [tab] = await chrome.tabs.query({
				active: true,
				currentWindow: true,
			});
			await runCapture(tab, message.question);
			sendResponse({ ok: true });
		})();
		return true; // keep the message channel open for the async response
	}

	if (message.type === "GODMODE_ASK_FOLLOWUP") {
		const tabId = sender.tab?.id;
		if (tabId != null) runFollowup(tabId, message.question);
		return false;
	}

	return false;
});

chrome.tabs.onRemoved.addListener((tabId) => sessions.delete(tabId));
