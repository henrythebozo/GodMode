const Provider = require('./provider');

class DeepSeek extends Provider {
	static webviewId = 'webviewDEEPSEEK';
	static fullName = 'DeepSeek Chat';
	static shortName = 'DeepSeek';

	static url = 'https://chat.deepseek.com/';

	static inputSelectors = ['textarea#chat-input', 'textarea'];

	// no stable button selector — the base class falls back to pressing Enter
	static submitSelectors = [];

	static isEnabled() {
		return window.electron.electronStore.get(`${this.webviewId}Enabled`, false);
	}
}

module.exports = DeepSeek;
