const Provider = require('./provider');

class Perplexity extends Provider {
	static webviewId = 'webviewPerplexity';
	static fullName = 'Perplexity';
	static shortName = 'Perplexity';

	static url = 'https://www.perplexity.ai/';

	// current UI uses a contenteditable div with id "ask-input"
	static inputSelectors = [
		'#ask-input',
		'div[contenteditable="true"]',
		'textarea[placeholder*="Ask"]',
	];

	static submitSelectors = [
		'button[data-testid="submit-button"]',
		'button[aria-label*="Submit"]',
	];

	static isEnabled() {
		return window.electron.electronStore.get(`${this.webviewId}Enabled`, true);
	}
}

module.exports = Perplexity;
