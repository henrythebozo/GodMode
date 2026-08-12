const DEFAULT_MODEL = "claude-sonnet-5";
const DEFAULT_PROMPT =
	"Answer the question shown in this screenshot. If there's no explicit question, briefly explain what's on screen.";

const apiKeyEl = document.getElementById("apiKey");
const modelEl = document.getElementById("model");
const promptEl = document.getElementById("defaultPrompt");
const savedEl = document.getElementById("saved");

async function load() {
	const { apiKey, model, defaultPrompt } = await chrome.storage.local.get([
		"apiKey",
		"model",
		"defaultPrompt",
	]);
	apiKeyEl.value = apiKey || "";
	modelEl.value = model || DEFAULT_MODEL;
	promptEl.value = defaultPrompt || DEFAULT_PROMPT;
}

document.getElementById("save").addEventListener("click", async () => {
	await chrome.storage.local.set({
		apiKey: apiKeyEl.value.trim(),
		model: modelEl.value,
		defaultPrompt: promptEl.value.trim() || DEFAULT_PROMPT,
	});
	savedEl.textContent = "Saved.";
	setTimeout(() => (savedEl.textContent = ""), 1500);
});

load();
