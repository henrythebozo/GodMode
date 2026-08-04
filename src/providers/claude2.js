const Provider = require('./provider');

class Claude2 extends Provider {
	static webviewId = 'webviewCLAUDE2';
	static fullName = 'Anthropic Claude';
	static shortName = 'Claude';

	static url = 'https://claude.ai/new';

	static inputSelectors = [
		'div[contenteditable="true"].ProseMirror',
		'div[aria-label*="Claude"][contenteditable="true"]',
		'div[contenteditable="true"]',
	];

	static submitSelectors = [
		'button[aria-label="Send message"]',
		'button[aria-label="Send Message"]',
		'button[aria-label*="Send"]',
	];

	static isEnabled() {
		return window.electron.electronStore.get(`${this.webviewId}Enabled`, true);
	}
}

module.exports = Claude2;
