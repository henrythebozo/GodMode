const statusEl = document.getElementById("status");
const needsKeyEl = document.getElementById("needsKey");
const questionEl = document.getElementById("question");
const captureBtn = document.getElementById("capture");
const shortcutLabel = document.getElementById("shortcutLabel");

async function init() {
	const { apiKey } = await chrome.storage.local.get(["apiKey"]);
	needsKeyEl.style.display = apiKey ? "none" : "block";

	const commands = await chrome.commands.getAll();
	const cmd = commands.find((c) => c.name === "capture-and-ask");
	if (cmd?.shortcut) shortcutLabel.textContent = cmd.shortcut;
}

captureBtn.addEventListener("click", async () => {
	captureBtn.disabled = true;
	statusEl.textContent = "Capturing…";
	try {
		await chrome.runtime.sendMessage({
			type: "GODMODE_TRIGGER_CAPTURE",
			question: questionEl.value,
		});
		statusEl.textContent = "Sent — check the page for the answer.";
	} catch (err) {
		statusEl.textContent = `Error: ${err.message}`;
	} finally {
		captureBtn.disabled = false;
	}
});

document.getElementById("openOptions").addEventListener("click", () => {
	chrome.runtime.openOptionsPage();
});

init();
