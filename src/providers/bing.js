const Provider = require('./provider');

class Bing extends Provider {
	// webviewId kept as BING for backwards compat with stored user settings
	static webviewId = 'webviewBING';
	static fullName = 'Microsoft Copilot';
	static shortName = 'Copilot';

	static url = 'https://copilot.microsoft.com/';

	static inputSelectors = [
		'textarea#userInput',
		'textarea[placeholder]',
		'div[contenteditable="true"]',
	];

	static submitSelectors = [
		'button[data-testid="submit-button"]',
		'button[aria-label*="Submit"]',
		'button[title*="Submit"]',
	];

	static isEnabled() {
		return window.electron.electronStore.get(`${this.webviewId}Enabled`, false);
	}
}

module.exports = Bing;
