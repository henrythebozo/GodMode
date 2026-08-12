// GodMode Screen Answers — background service worker
//
// Flow: user hits the keyboard shortcut (or the popup button) -> we screenshot
// the visible tab -> stream the answer from Claude, token by token, into an
// overlay injected into the page by content.js. Everything (API key, model,
// default prompt) lives in chrome.storage.local; nothing leaves the browser
// except the request straight to api.anthropic.com.

const ANTHROPIC_API_URL = "https://api.anthropic.com/v1/messages";
const DEFAULT_MODEL = "claude-sonnet-5";
const DEFAULT_PROMPT =
	"Answer the question shown in this screenshot. If there's no explicit question, briefly explain what's on screen.";
const SYSTEM_PROMPT =
	"You're talking to a user through a browser extension that just showed you a screenshot of their screen. " +
	"Answer with the same depth, accuracy, and care you'd use in a normal conversation — don't hold back detail " +
	"or oversimplify just because the channel is a small overlay. Use markdown (code fences, lists, bold) where " +
	"it genuinely helps readability, but keep the reply focused on what was actually asked.";

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

/**
 * Streams a Messages API completion, calling onDelta(fullTextSoFar) as tokens
 * arrive. Returns the final full text.
 */
async function streamClaude(messages, { apiKey, model }, onDelta) {
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
			max_tokens: 4096,
			system: SYSTEM_PROMPT,
			messages,
			stream: true,
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

	const reader = res.body.getReader();
	const decoder = new TextDecoder();
	let buffer = "";
	let fullText = "";

	while (true) {
		const { value, done } = await reader.read();
		if (done) break;
		buffer += decoder.decode(value, { stream: true });

		const lines = buffer.split("\n");
		buffer = lines.pop(); // keep the trailing partial line for next chunk

		for (const line of lines) {
			if (!line.startsWith("data:")) continue;
			const jsonStr = line.slice(5).trim();
			if (!jsonStr) continue;

			let evt;
			try {
				evt = JSON.parse(jsonStr);
			} catch {
				continue;
			}

			if (evt.type === "content_block_delta" && evt.delta?.type === "text_delta") {
				fullText += evt.delta.text;
				onDelta(fullText);
			} else if (evt.type === "error") {
				throw new Error(evt.error?.message || "Streaming error");
			}
		}
	}

	return fullText;
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

/**
 * Throttles token-by-token deltas down to a sane message-passing rate while
 * still flushing the final text immediately when the stream ends.
 */
function makeStreamRelay(tabId, minIntervalMs = 60) {
	let lastSent = 0;
	let timer = null;
	let latest = "";

	function flush() {
		timer = null;
		lastSent = Date.now();
		sendToTab(tabId, { type: "GODMODE_STREAM_DELTA", text: latest });
	}

	return {
		update(text) {
			latest = text;
			const elapsed = Date.now() - lastSent;
			if (elapsed >= minIntervalMs) {
				if (timer) clearTimeout(timer);
				flush();
			} else if (!timer) {
				timer = setTimeout(flush, minIntervalMs - elapsed);
			}
		},
		finish(finalText) {
			if (timer) clearTimeout(timer);
			timer = null;
			latest = finalText;
			sendToTab(tabId, { type: "GODMODE_STREAM_DONE", text: finalText });
		},
	};
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

	const relay = makeStreamRelay(tab.id);
	try {
		const answer = await streamClaude(messages, settings, (text) => relay.update(text));
		sessions.get(tab.id).messages.push({ role: "assistant", content: answer });
		relay.finish(answer);
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

	const relay = makeStreamRelay(tabId);
	try {
		const answer = await streamClaude(session.messages, settings, (text) => relay.update(text));
		session.messages.push({ role: "assistant", content: answer });
		relay.finish(answer);
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
