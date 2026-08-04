const Provider = require('./provider');

class Bard extends Provider {
	// webviewId kept as BARD for backwards compat with stored user settings
	static webviewId = 'webviewBARD';
	static fullName = 'Google Gemini';
	static shortName = 'Gemini';

	static url = 'https://gemini.google.com/app';

	// Gemini's prompt box is a Quill editor inside <rich-textarea>
	static inputSelectors = [
		'rich-textarea .ql-editor',
		'.ql-editor',
		'div[contenteditable="true"]',
	];

	static submitSelectors = [
		'button.send-button',
		'button[aria-label*="Send"]',
		'button[mattooltip*="Send"]',
	];

	static handleDarkMode(isDarkMode) {
		if (isDarkMode) {
			this.getWebview().executeJavaScript(`{
        document.querySelector('body').classList.add('dark-theme');
        document.querySelector('body').classList.remove('light-theme');
      }`);
		} else {
			this.getWebview().executeJavaScript(`{
        document.querySelector('body').classList.add('light-theme');
        document.querySelector('body').classList.remove('dark-theme');
      }`);
		}
	}

	static isEnabled() {
		return window.electron.electronStore.get(`${this.webviewId}Enabled`, true);
	}
}

module.exports = Bard;
