const Provider = require('./provider');

class Grok extends Provider {
	static webviewId = 'webviewGROK';
	static fullName = 'xAI Grok';
	static shortName = 'Grok';

	static url = 'https://grok.com/';

	static inputSelectors = [
		'textarea[aria-label*="Grok"]',
		'textarea[placeholder*="Grok"]',
		'form textarea',
		'div[contenteditable="true"]',
	];

	static submitSelectors = [
		'form button[type="submit"]',
		'button[aria-label*="Submit"]',
	];

	static isEnabled() {
		return window.electron.electronStore.get(`${this.webviewId}Enabled`, false);
	}
}

module.exports = Grok;
