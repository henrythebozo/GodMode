// const { ipcRenderer } = require('electron');
// const log = require('electron-log');

class Provider {
	static webviewId = '';

	static getWebview() {
		// log('Provider.getWebview()', document.getElementById(this.webviewId));
		return document.getElementById(this.webviewId);
	}

	static url = '';

	// Modern providers declare CSS selectors instead of hand-rolling injection
	// scripts. Each list is tried in order; the first match wins, so when a
	// site ships a redesign the fix is usually just a new selector at the
	// front of the list.
	static inputSelectors = [];
	static submitSelectors = [];

	static paneId() {
		return `${this.name.toLowerCase()}Pane`;
	}

	static setupCustomPasteBehavior() {
		this.getWebview().addEventListener('dom-ready', () => {
			this.getWebview().executeJavaScript(`{
					document.addEventListener('paste', (event) => {
					event.preventDefault();
					var text = event.clipboardData.getData('text');
					var activeElement = document.activeElement;

					// sometimes the active element needs  a "wake up" before paste (swyx: not entirely sure this works...)
					// Create a KeyboardEvent
					var event = new KeyboardEvent('keydown', {
						key: ' ',
						code: 'Space',
						which: 32,
						keyCode: 32,
						bubbles: true
					});

					// Dispatch the event to the active element
					activeElement.dispatchEvent(event);

					var start = activeElement.selectionStart;
					var end = activeElement.selectionEnd;
					activeElement.value = activeElement.value.slice(0, start) + text + activeElement.value.slice(end);
					activeElement.selectionStart = activeElement.selectionEnd = start + text.length;
					});
				}`);
		});
	}

	// execCommand('insertText') goes through the browser's editing pipeline, so
	// React/ProseMirror/Quill/Lexical inputs all register the change — unlike
	// setting .value or .innerHTML directly.
	static inputScript(input) {
		return `(() => {
			const sels = ${JSON.stringify(this.inputSelectors)};
			let el = null;
			for (const s of sels) { try { el = document.querySelector(s); } catch (e) {} if (el) break; }
			if (!el) return;
			el.focus();
			if (el.tagName === 'TEXTAREA' || el.tagName === 'INPUT') el.select();
			else document.execCommand('selectAll', false, null);
			const text = \`${input}\`;
			if (text) document.execCommand('insertText', false, text);
			else document.execCommand('delete', false, null);
			el.dispatchEvent(new Event('input', { bubbles: true }));
		})()`;
	}

	static submitScript() {
		return `(() => {
			const btnSels = ${JSON.stringify(this.submitSelectors)};
			let btn = null;
			for (const s of btnSels) { try { btn = document.querySelector(s); } catch (e) {} if (btn) break; }
			if (btn) { btn.focus(); btn.disabled = false; btn.click(); return; }
			// no button found: press Enter in the input instead
			const sels = ${JSON.stringify(this.inputSelectors)};
			let el = null;
			for (const s of sels) { try { el = document.querySelector(s); } catch (e) {} if (el) break; }
			if (!el) return;
			el.focus();
			const opts = { key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true, cancelable: true };
			el.dispatchEvent(new KeyboardEvent('keydown', opts));
			el.dispatchEvent(new KeyboardEvent('keyup', opts));
		})()`;
	}

	static handleInput(input) {
		if (!this.inputSelectors.length) {
			throw new Error(`Provider ${this.name} must implement handleInput()`);
		}
		this.getWebview().executeJavaScript(this.inputScript(input));
	}

	static handleSubmit() {
		if (!this.inputSelectors.length && !this.submitSelectors.length) {
			throw new Error(`Provider ${this.name} must implement handleSubmit()`);
		}
		this.getWebview().executeJavaScript(this.submitScript());
	}

	static handleCss() {
		// most providers need no CSS surgery; override when they do
	}

	// Some providers will have their own dark mode implementation
	static handleDarkMode(isDarkMode) {
		// Implement dark or light mode using prodiver-specific code
		if (isDarkMode) {
			this.getWebview().executeJavaScript(`{
				document.documentElement.classList.add('dark');
				document.documentElement.classList.remove('light');
			}`);
		} else {
			this.getWebview().executeJavaScript(`{
				document.documentElement.classList.add('light');
				document.documentElement.classList.remove('dark');
			}`);
		}
	}

	static getUserAgent() {
		// realistic, current browser UA with no Electron mention — several
		// providers (especially Google login) reject old or nonstandard UAs
		return 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';
	}

	static isEnabled() {
		return window.electron.electronStore.get(`${this.webviewId}Enabled`);
	}

	static setEnabled(state) {
		window.electron.electronStore.set(`${this.webviewId}Enabled`, state);
	}
}

module.exports = Provider;
