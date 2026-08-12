# GodMode Screen Answers (Chrome extension)

A small Manifest V3 Chrome extension: hit a keyboard shortcut, it screenshots
the current tab, sends it to Claude with a question, and shows the answer in
a floating card injected on the page. You can also trigger it from the
toolbar popup and ask follow-ups without recapturing.

Everything runs client-side — your Anthropic API key is stored in
`chrome.storage.local` and requests go straight from your browser to
`api.anthropic.com`. No GodMode server is involved.

## Load it locally

1. Open `chrome://extensions`.
2. Enable **Developer mode** (top right).
3. Click **Load unpacked** and select this `extension/` folder.
4. Click the extension's icon → **Options** and paste an Anthropic API key
   (get one at https://console.anthropic.com/settings/keys).

## Use it

- Press **Ctrl+Shift+Y** (**Cmd+Shift+Y** on Mac) on any page to capture it
  and ask the default question ("answer the question shown in this
  screenshot"). Customize the shortcut at `chrome://extensions/shortcuts`,
  and the default question in Options.
- Or click the toolbar icon, optionally type a specific question, and hit
  **Capture & Ask**.
- Once an answer appears, use the input at the bottom of the floating card
  to ask follow-ups — they reuse the same screenshot as context.

## Files

| File               | Purpose                                                    |
| ------------------ | ----------------------------------------------------------- |
| `manifest.json`     | MV3 manifest — permissions, shortcut, content script wiring |
| `background.js`     | Service worker: captures the tab, calls the Claude API      |
| `content.js`/`.css` | Injects the floating answer card into the page              |
| `popup.html`/`.js`  | Toolbar popup for manual capture + status                   |
| `options.html`/`.js`| API key, model, and default-question settings               |

## Notes / limitations

- `chrome.tabs.captureVisibleTab` only captures the visible viewport of the
  active tab (not the full page, not other monitors/windows).
- It can't run on `chrome://` pages or the Chrome Web Store, per Chrome's
  extension restrictions.
- No API key ever leaves your machine except in the direct request to
  Anthropic's API.
