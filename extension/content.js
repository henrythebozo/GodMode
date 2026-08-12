// GodMode Screen Answers — content script
//
// Renders a small floating card (inside a shadow root, so page CSS can't
// clash with it) that shows the screenshot thumbnail, a loading state, and
// Claude's answer, plus a box for follow-up questions.

(() => {
	let host = document.getElementById("godmode-overlay-host");
	let shadow;
	let els = {};

	function ensureOverlay() {
		if (host) return;

		host = document.createElement("div");
		host.id = "godmode-overlay-host";
		document.documentElement.appendChild(host);
		shadow = host.attachShadow({ mode: "open" });

		shadow.innerHTML = `
			<style>
				:host { all: initial; }
				.card {
					position: fixed;
					bottom: 20px;
					right: 20px;
					width: 340px;
					max-height: 70vh;
					display: flex;
					flex-direction: column;
					background: #111827;
					color: #f3f4f6;
					border-radius: 12px;
					box-shadow: 0 10px 40px rgba(0,0,0,0.45);
					font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
					font-size: 13px;
					line-height: 1.45;
					overflow: hidden;
					border: 1px solid rgba(255,255,255,0.08);
				}
				.header {
					display: flex;
					align-items: center;
					justify-content: space-between;
					padding: 8px 12px;
					background: #1f2937;
					cursor: default;
					flex: none;
				}
				.title {
					font-weight: 600;
					font-size: 12px;
					color: #a5b4fc;
					letter-spacing: 0.01em;
				}
				.close {
					background: none;
					border: none;
					color: #9ca3af;
					cursor: pointer;
					font-size: 16px;
					line-height: 1;
					padding: 2px 4px;
					border-radius: 4px;
				}
				.close:hover { background: rgba(255,255,255,0.08); color: #fff; }
				.body {
					padding: 10px 12px;
					overflow-y: auto;
					flex: 1 1 auto;
				}
				.thumb {
					width: 100%;
					border-radius: 8px;
					margin-bottom: 8px;
					display: block;
					border: 1px solid rgba(255,255,255,0.08);
				}
				.answer {
					white-space: pre-wrap;
					word-break: break-word;
				}
				.status {
					color: #9ca3af;
					display: flex;
					align-items: center;
					gap: 8px;
				}
				.spinner {
					width: 14px;
					height: 14px;
					border-radius: 50%;
					border: 2px solid rgba(255,255,255,0.2);
					border-top-color: #a5b4fc;
					animation: spin 0.8s linear infinite;
					flex: none;
				}
				@keyframes spin { to { transform: rotate(360deg); } }
				.error { color: #fca5a5; }
				.footer {
					display: flex;
					gap: 6px;
					padding: 8px;
					background: #1f2937;
					flex: none;
				}
				.footer input {
					flex: 1;
					background: #111827;
					border: 1px solid rgba(255,255,255,0.12);
					border-radius: 6px;
					color: #f3f4f6;
					padding: 6px 8px;
					font-size: 12px;
					outline: none;
				}
				.footer input:focus { border-color: #6366f1; }
				.footer button {
					background: #4f46e5;
					border: none;
					color: white;
					border-radius: 6px;
					padding: 0 12px;
					font-size: 12px;
					cursor: pointer;
					font-weight: 600;
				}
				.footer button:hover { background: #4338ca; }
				.footer button:disabled { opacity: 0.5; cursor: default; }
			</style>
			<div class="card">
				<div class="header">
					<span class="title">GodMode</span>
					<button class="close" title="Close">&times;</button>
				</div>
				<div class="body"><div class="status">Ready.</div></div>
				<div class="footer">
					<input type="text" placeholder="Ask a follow-up…" />
					<button type="button">Ask</button>
				</div>
			</div>
		`;

		els.body = shadow.querySelector(".body");
		els.close = shadow.querySelector(".close");
		els.input = shadow.querySelector(".footer input");
		els.send = shadow.querySelector(".footer button");

		els.close.addEventListener("click", () => host.remove());
		const sendFollowup = () => {
			const question = els.input.value.trim();
			if (!question) return;
			els.input.value = "";
			chrome.runtime.sendMessage({ type: "GODMODE_ASK_FOLLOWUP", question });
			appendUserQuestion(question);
		};
		els.send.addEventListener("click", sendFollowup);
		els.input.addEventListener("keydown", (e) => {
			if (e.key === "Enter") sendFollowup();
		});
	}

	function appendUserQuestion(question) {
		const p = document.createElement("div");
		p.className = "status";
		p.style.marginTop = "10px";
		p.textContent = `↳ ${question}`;
		els.body.appendChild(p);
		els.body.scrollTop = els.body.scrollHeight;
	}

	function showLoading(screenshot) {
		ensureOverlay();
		if (screenshot) {
			// Fresh capture — reset the card entirely.
			els.body.innerHTML = "";
			const img = document.createElement("img");
			img.className = "thumb";
			img.src = screenshot;
			els.body.appendChild(img);
		}
		const status = document.createElement("div");
		status.className = "status loading-status";
		status.innerHTML = `<span class="spinner"></span> Asking Claude…`;
		els.body.appendChild(status);
		els.body.scrollTop = els.body.scrollHeight;
	}

	function showAnswer(answer) {
		ensureOverlay();
		els.body.querySelector(".loading-status")?.remove();
		const div = document.createElement("div");
		div.className = "answer";
		div.textContent = answer || "(no answer)";
		els.body.appendChild(div);
		els.body.scrollTop = els.body.scrollHeight;
	}

	function showError(error) {
		ensureOverlay();
		els.body.querySelector(".loading-status")?.remove();
		const div = document.createElement("div");
		div.className = "error";
		div.textContent = `⚠ ${error}`;
		els.body.appendChild(div);
		els.body.scrollTop = els.body.scrollHeight;
	}

	chrome.runtime.onMessage.addListener((message) => {
		switch (message.type) {
			case "GODMODE_SHOW_LOADING":
				showLoading(message.screenshot);
				break;
			case "GODMODE_SHOW_ANSWER":
				showAnswer(message.answer);
				break;
			case "GODMODE_SHOW_ERROR":
				showError(message.error);
				break;
		}
	});
})();
