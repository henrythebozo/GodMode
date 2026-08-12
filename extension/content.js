// GodMode Screen Answers — content script
//
// Renders a small floating card (inside a shadow root, so page CSS can't
// clash with it) that shows the screenshot thumbnail, a live-streamed,
// markdown-rendered answer from Claude, and a box for follow-up questions.

(() => {
	let host = document.getElementById("godmode-overlay-host");
	let shadow;
	let els = {};

	// ---- tiny, dependency-free markdown -> safe HTML -------------------------
	// Escapes everything first, then only ever inserts our own controlled tags,
	// so there's no way for the model's output to inject arbitrary markup.

	function escapeHtml(s) {
		return s
			.replace(/&/g, "&amp;")
			.replace(/</g, "&lt;")
			.replace(/>/g, "&gt;");
	}

	function renderInlineSpans(text) {
		let out = escapeHtml(text);
		out = out.replace(/`([^`]+)`/g, "<code>$1</code>");
		out = out.replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>");
		out = out.replace(/(^|[^*])\*([^*\n]+)\*(?!\*)/g, "$1<em>$2</em>");
		out = out.replace(
			/\[([^\]]+)\]\((https?:\/\/[^\s)]+)\)/g,
			'<a href="$2" target="_blank" rel="noopener noreferrer">$1</a>',
		);
		return out;
	}

	function renderTextBlock(text) {
		const lines = text.split("\n");
		let html = "";
		let inList = false;
		for (const line of lines) {
			const listMatch = line.match(/^\s*[-*]\s+(.*)/);
			const headingMatch = line.match(/^(#{1,4})\s+(.*)/);
			if (listMatch) {
				if (!inList) {
					html += "<ul>";
					inList = true;
				}
				html += `<li>${renderInlineSpans(listMatch[1])}</li>`;
				continue;
			}
			if (inList) {
				html += "</ul>";
				inList = false;
			}
			if (headingMatch) {
				const level = Math.min(headingMatch[1].length + 2, 6);
				html += `<h${level} class="md-h">${renderInlineSpans(headingMatch[2])}</h${level}>`;
			} else if (line.trim() === "") {
				html += "<br>";
			} else {
				html += `<p>${renderInlineSpans(line)}</p>`;
			}
		}
		if (inList) html += "</ul>";
		return html;
	}

	function renderMarkdown(markdown) {
		const codeFence = /```(\w*)\n?([\s\S]*?)```/g;
		let html = "";
		let lastIndex = 0;
		let match;
		while ((match = codeFence.exec(markdown))) {
			html += renderTextBlock(markdown.slice(lastIndex, match.index));
			const lang = match[1] || "";
			html += `<pre><code class="lang-${escapeHtml(lang)}">${escapeHtml(match[2])}</code></pre>`;
			lastIndex = codeFence.lastIndex;
		}
		html += renderTextBlock(markdown.slice(lastIndex));
		return html;
	}

	// ---- overlay UI ------------------------------------------------------

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
					width: 360px;
					max-height: 70vh;
					display: flex;
					flex-direction: column;
					background: #111827;
					color: #f3f4f6;
					border-radius: 12px;
					box-shadow: 0 10px 40px rgba(0,0,0,0.45);
					font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
					font-size: 13px;
					line-height: 1.5;
					overflow: hidden;
					border: 1px solid rgba(255,255,255,0.08);
				}
				.header {
					display: flex;
					align-items: center;
					justify-content: space-between;
					padding: 8px 12px;
					background: #1f2937;
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
				.answer p { margin: 0 0 8px; }
				.answer p:last-child { margin-bottom: 0; }
				.answer ul { margin: 4px 0 8px; padding-left: 18px; }
				.answer li { margin-bottom: 2px; }
				.answer .md-h { margin: 10px 0 4px; font-size: 13px; color: #c7d2fe; }
				.answer code {
					background: rgba(255,255,255,0.1);
					padding: 1px 5px;
					border-radius: 4px;
					font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
					font-size: 11.5px;
				}
				.answer pre {
					background: #0b1220;
					border: 1px solid rgba(255,255,255,0.08);
					border-radius: 8px;
					padding: 8px 10px;
					overflow-x: auto;
					margin: 6px 0 10px;
				}
				.answer pre code { background: none; padding: 0; font-size: 11.5px; }
				.answer a { color: #a5b4fc; }
				.cursor {
					display: inline-block;
					width: 6px;
					height: 13px;
					background: #a5b4fc;
					margin-left: 2px;
					vertical-align: text-bottom;
					animation: blink 1s step-start infinite;
				}
				@keyframes blink { 50% { opacity: 0; } }
				.status {
					color: #9ca3af;
					display: flex;
					align-items: center;
					gap: 8px;
				}
				.followup-echo {
					color: #9ca3af;
					margin: 10px 0 6px;
					padding-top: 8px;
					border-top: 1px dashed rgba(255,255,255,0.1);
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
		els.currentAnswer = null;

		els.close.addEventListener("click", () => {
			host.remove();
			host = null;
		});
		const sendFollowup = () => {
			const question = els.input.value.trim();
			if (!question) return;
			els.input.value = "";
			chrome.runtime.sendMessage({ type: "GODMODE_ASK_FOLLOWUP", question });
			appendUserQuestion(question);
			showLoading();
		};
		els.send.addEventListener("click", sendFollowup);
		els.input.addEventListener("keydown", (e) => {
			if (e.key === "Enter") sendFollowup();
		});
	}

	function appendUserQuestion(question) {
		const p = document.createElement("div");
		p.className = "followup-echo";
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
		els.currentAnswer = null; // next delta starts a fresh answer block
		const status = document.createElement("div");
		status.className = "status loading-status";
		status.innerHTML = `<span class="spinner"></span> Asking Claude…`;
		els.body.appendChild(status);
		els.body.scrollTop = els.body.scrollHeight;
	}

	function updateStreamingAnswer(text, done) {
		ensureOverlay();
		els.body.querySelector(".loading-status")?.remove();
		if (!els.currentAnswer) {
			els.currentAnswer = document.createElement("div");
			els.currentAnswer.className = "answer";
			els.body.appendChild(els.currentAnswer);
		}
		els.currentAnswer.innerHTML =
			renderMarkdown(text) + (done ? "" : '<span class="cursor"></span>');
		if (done) els.currentAnswer = null; // next turn gets its own block
		els.body.scrollTop = els.body.scrollHeight;
	}

	function showError(error) {
		ensureOverlay();
		els.body.querySelector(".loading-status")?.remove();
		const div = document.createElement("div");
		div.className = "error";
		div.textContent = `⚠ ${error}`;
		els.body.appendChild(div);
		els.currentAnswer = null;
		els.body.scrollTop = els.body.scrollHeight;
	}

	chrome.runtime.onMessage.addListener((message) => {
		switch (message.type) {
			case "GODMODE_SHOW_LOADING":
				showLoading(message.screenshot);
				break;
			case "GODMODE_STREAM_DELTA":
				updateStreamingAnswer(message.text, false);
				break;
			case "GODMODE_STREAM_DONE":
				updateStreamingAnswer(message.text, true);
				break;
			case "GODMODE_SHOW_ERROR":
				showError(message.error);
				break;
		}
	});
})();
