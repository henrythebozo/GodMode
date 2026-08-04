const Provider = require('./provider');

class OpenAI extends Provider {
	static webviewId = 'webviewOAI';
	static fullName = 'OpenAI ChatGPT';
	static shortName = 'ChatGPT';

	static url = 'https://chatgpt.com/';

	// #prompt-textarea is a ProseMirror contenteditable div in the current UI
	static inputSelectors = [
		'#prompt-textarea',
		'div[contenteditable="true"].ProseMirror',
		'textarea[data-testid="prompt-textarea"]',
	];

	static submitSelectors = [
		'button[data-testid="composer-submit-button"]',
		'button[data-testid="send-button"]',
		'button[aria-label*="Send"]',
	];

	static handleCss() {
		this.getWebview().addEventListener('dom-ready', () => {
			this.getWebview().insertCSS(`
        body {
          scrollbar-width: none;
        }
        `);
		});
	}

	static isEnabled() {
		return window.electron.electronStore.get(`${this.webviewId}Enabled`, true);
	}
}

module.exports = OpenAI;
