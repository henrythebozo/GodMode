# 🐣 GodMode - the smol AI Chat Browser

This is a dedicated chat browser that only does one thing: help you quickly access **the full webapps** of ChatGPT, Claude 2, Perplexity, Bing and more **with a single keyboard shortcut (Cmd+Shift+G)**.

![image](https://github.com/smol-ai/GodMode/assets/6764957/90f4bab4-e406-4507-b37e-8c8d80d18f15)

([click for video](https://twitter.com/swyx/status/1692988634364871032))

Whatever is typed at the bottom is entered into all **web apps** simultaneously, however if you wish to explore one further than the other you can do so independently since they are just webviews.

## 🌐 Henry OS (web + iPhone)

There is also a browser version in [`docs/index.html`](docs/index.html) — a single
self-contained HTML file with the same one-prompt-to-many-models experience,
installable to an iPhone home screen. Because websites cannot embed the
ChatGPT/Claude/Gemini web apps (those sites block iframes), it talks to models
over their APIs instead: add one [OpenRouter](https://openrouter.ai) key for
300+ models, and/or your own OpenAI, Anthropic, Moonshot and Perplexity keys.
Ask once and every model answers at the same time, then Claude writes a Council
briefing — the combined answer, what each model said, and where they disagree.
Keys are stored only in your browser.

To host it free with GitHub Pages: repo **Settings → Pages → Deploy from a
branch → `main` / `docs`**. Or run it on localhost with `npm run web`
(no install needed — plain Node) and open `http://localhost:8741`; the
command also prints a Wi-Fi address you can open from your phone.

## 🎙️ Jarvis (voice assistant)

[`docs/jarvis.html`](docs/jarvis.html) is a second, self-contained page — a
voice-first personal assistant in the style of Iron Man's Jarvis. Open it from
the button next to "Henry OS" in the sidebar, or go straight to
`/jarvis.html`.

- **Talk to it.** Tap the mic and speak, hold a conversation with "wake word"
  mode (say "Jarvis" to wake it, hands-free), or just type. It answers out
  loud with the browser's built-in text-to-speech — pick a voice, rate, and
  pitch in Settings.
- **The home screen *is* the assistant** — greeting at the top, orb filling
  the middle, composer at the bottom, no card or panel around it. Quick
  access, gauges, upcoming tasks, connected apps and your business all live
  under **Overview** in the nav.
- **It remembers you.** Ask it to remember a fact ("remember that I'm
  allergic to shellfish") and it'll recall it in every future conversation.
- **It gets things done.** Built-in tools for reminders ("remind me to call
  Sam in 20 minutes"), quick notes, live weather (no API key needed), the
  time, a system status readout, and opening links or web searches.
- **It takes and analyzes notes, Otter-style.** Tap the record button to
  transcribe a conversation or meeting live (separate from the command mic),
  then hit "Analyze" on a saved recording for an AI summary, key points, and
  action items. Ask Jarvis "what did we cover in that meeting?" and it'll
  pull the answer straight from a saved recording.
- **It runs your smart home.** A virtual home (lights, a lock, a thermostat,
  "Good Morning"/"Good Night" scenes) works immediately by voice or from the
  Home panel — no setup. Flip on Home Assistant in Settings to control real
  devices instead (Hue, Nest, SmartThings-paired gear, Sonos, and most other
  brands go through it).
- **It can put multiple AIs to work together.** Add more than one model in
  Settings and turn on Team mode: Jarvis quietly consults every model on your
  question in parallel, then answers you in one voice using the best of what
  they said. Switch which model leads at any time.
- **It can generate images and video.** Add a [Higgsfield](https://higgsfield.ai)
  API key in Settings and ask Jarvis to make you a picture (or a video, once
  you point it at a video model) — it generates it and opens the result.
- **It knows your calendar (read-only).** Upload an exported `.ics` file (or
  sync a URL, for feeds that allow cross-origin requests) in Settings →
  Calendar and Jarvis can tell you what's next, and includes it in the
  dashboard's Upcoming list and the daily briefing.
- **It can give you a daily briefing.** Opt in and pick a time in Settings →
  Persona — weather, today's reminders, and a memory highlight, spoken once
  a day while the app's open.
- Global search (sidebar/top bar icon) across memory, notes, reminders,
  recordings, and chat history. Export/import a full backup, or reset
  everything, from Settings → Data.
- Unlocking a door by voice always pops an in-app confirmation first —
  enforced in code, not just prompted to the model.
- **Give it a business to focus on.** Set up your business in Settings →
  Business (name, what it does, background) and Jarvis factors it into every
  answer. Upload a logo or let it generate a monogram, and import plain-text
  documents — briefs, price lists, notes — that it reads when a question calls
  for them.
- **Calm, flat interface** — warm neutral surfaces, a single clay accent, no
  uppercase shouting. Dark by default; Settings → Persona → Appearance
  switches to light (boot intro included) and can dial frosted glass back in
  if you want depth.
- **Works offline.** Everything Jarvis knows lives on your device, so with the
  app installed (Add to Home Screen) your memory, reminders, notes and
  recordings all still open with no connection — only the AI, weather and
  smart-home calls need the network.
- **Mobile navigation** is a menu button top-left that opens full-screen —
  no bottom tab bar. The composer stays pinned at the bottom with the mic
  beside Send. Desktop keeps its permanent sidebar.
- **Keyboard shortcuts:** `⌘/Ctrl+K` search, `⌘/Ctrl+J` activity,
  `⌘/Ctrl+,` settings, `/` jump to the composer, `M` toggle the mic.
- If your lead model fails (rate limit, outage, bad key), Jarvis automatically
  falls back to the next model you've configured rather than dropping the turn.
- **Sign in rather than paste a key.** One button runs
  [OpenRouter](https://openrouter.ai)'s OAuth (PKCE, no client secret, nothing
  to register) and Jarvis is connected — and since OpenRouter brokers Claude,
  Gemini and GPT, that one sign-in reaches all three. It is the only one of the
  four that a page with no server *can* sign you into: Anthropic's OAuth is
  reserved for Anthropic's own apps and a claude.ai login grants no API access,
  and Google's wants a Cloud project and a consent screen — more work than the
  key it would replace. Bringing your own key still works exactly as before: an
  OpenRouter key, or your own OpenAI/Anthropic/[Gemini](https://ai.google.dev)
  key, stored only on your device. Out of the box it runs Team mode with Claude Sonnet 5 leading and
  Opus 5 consulting; switch to a single model in Settings → Account to halve
  the per-question cost.
- **And where a key is the only option, it takes one paste and no typing.**
  Each provider has a *get one ↗* link straight to the page that key lives on,
  and once you have copied it you can paste it **anywhere in Jarvis** — the
  composer, a note, wherever the cursor happens to be. Jarvis recognises which
  provider it belongs to from its shape, asks once, and files it; nothing lands
  in the box it would have been sent from, and a half-written message survives
  the interception. It never reads your clipboard — only a paste you performed.
  In the terminal the same idea is `pbpaste | jarvis key add`, and
  `jarvis key import` picks up whatever is already exported in your shell.

### 🧠 Memory is a graph, not a list

Everything Jarvis remembers is a **note** — a title, a folder, and a body — and
notes link to each other by writing a title in double square brackets inside
the text. The **Graph** view draws the result: notes as circles, folders as
hubs, and a hollow circle for anything you have linked to but not written yet.
Click a node to read it, and everything it is not connected to fades back.

Links live in the prose and nowhere else, so there is one copy of the truth and
it cannot drift out of step with the text. Renaming a note rewrites every link
pointing at it. **Suggest links** finds the ones you already wrote without
meaning to — a note saying "APEX is the project Noah helps with" is describing
an edge, it just has not got the brackets — and adds them both ways.

Nothing is ever deleted to make room. Any message in a chat can be saved
straight into memory with the button that appears on it. And rather than
posting your whole vault to the model on every turn, Jarvis scores the notes
against what you asked and follows one hop along their links, so asking about
someone also brings in the project their note points at.

### ⌨️ Jarvis in the terminal

[`cli/`](cli) is the same assistant as a **zero-dependency command-line tool**,
and the same memory graph as **plain markdown files on your disk** — a folder
you can open in Obsidian, commit to git, grep, or edit in vim.

```sh
cd cli && npm link && jarvis init

jarvis "what's on my plate today"
jarvis mem add "Noah starts school Sept 3" -f People -t Noah
jarvis mem link Noah "Homeschool Portal"
jarvis graph --open          # renders the whole vault and opens it
```

Node built-ins only — nothing to install, no lockfile, no build step. It takes
the same four providers, or point `baseUrl` at Ollama or any other
OpenAI-compatible server for a local model. Keys live in `~/.jarvis/`, never in
the vault, because the vault is the part you are meant to sync and share.

In Chrome or Edge, **Settings → Data → Vault folder** points the browser at
that same directory and syncs whole notes both ways — one vault, both halves,
Obsidian included. Elsewhere the bridge is a file you move across: `jarvis
export`, then Settings → Data → Import, and the other way round. Full setup and
command reference in [`cli/README.md`](cli/README.md).

### 📱 Jarvis for iOS

[`mobile-app/`](mobile-app) wraps Jarvis in a real native iOS app with
[Capacitor](https://capacitorjs.com), so it can ship on the App Store instead
of just living in a browser tab — including on-device voice recognition
(WKWebView doesn't have the Web Speech API, so the browser version alone
can't do this on iOS), reminders that fire as real notifications even when
the app is closed, and Siri Shortcuts ("Hey Siri, ask Jarvis…"). A Home
Screen widget is written but needs one manual Xcode step to enable. The
Xcode project is fully scaffolded; see
[`mobile-app/README.md`](mobile-app/README.md) for the remaining steps, which
need a Mac, Xcode, and your own Apple Developer account.

## Installation

**Install [here](https://github.com/smol-ai/GodMode/releases/latest)!** And then log in to Google on any one of the providers + refreshing logs you into most of the rest.
Google Bard seems to have weird auth requirements [we havent figured out yet](https://github.com/smol-ai/GodMode/issues/201) - logging into Google via Anthropic Claude first seems to be the most reliable right now while we figure it out.

Download:

- Arm64 for Apple Silicon Macs, non Arm64 (universal) for Intel Macs.
- We [just added Windows/Linux support](https://github.com/smol-ai/GodMode/pull/162), but it needs a lot of work. Help wanted!

You can also build from source, see instructions below.

## Mixture of Mixture of Experts

It's well discussed by now that [GPT4 is a mixture of experts model](https://twitter.com/swyx/status/1671272883379908608), which explains its great advancement over GPT3 while not sacrificing speed. It stands to reason that if you can run one chat and get results from all the top closed/open source models, you will get that much more diversity in results for what you seek. As a side benefit, we will add opt-in data submission soon so we can crowdsource statistics on win rates, niche advantages, and show them over time.

> “That's why it's always worth having a few philosophers around the place. One minute it's all is truth beauty and is beauty truth, and does a falling tree in the forest make a sound if there's no one there to hear it, and then just when you think they're going to start dribbling one of 'em says, incidentally, putting a thirty-foot parabolic reflector on a high place to shoot the rays of the sun at an enemy's ships would be a very interesting demonstration of optical principles.”
>
> ― [Terry Pratchett, Small Gods](https://www.goodreads.com/work/quotes/1636629-small-gods)

## Oh so this is like nat.dev?

Yes and no:

1. SOTA functionality is often released without API (eg: ChatGPT Code Interpreter, Bing Image Creator, Bard Multimodal Input, Claude Multifile Upload). **We insist on using webapps** so that you have full access to all functionality on launch day. We also made light/dark mode for each app, just for fun (`Cmd+Shift+L` (Aug update: currently broken in the GodMode rewrite, will fix))
2. This is a **secondary browser** that can be pulled up with a keyboard shortcut (`Cmd+Shift+G`, customizable). Feels a LOT faster than having it live in a browser window somewhere and is easy to pull up/dismiss during long generations.
3. Supports no-API models like Perplexity and Poe, and local models like LLaMa and Vicuna (via [OobaBooga](https://github.com/oobabooga/text-generation-webui)).
4. No paywall, build from source.
5. Fancy new features like PromptCritic (AI assisted prompt improvement)

## Supported LLM Providers

| Provider (default in **bold**)                                                          | Notes                                                                                                                                                                    |
| --------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **ChatGPT**                                                                             | Defaults to "[GPT4.5](https://www.latent.space/p/code-interpreter#details)"!                                                                                             |
| **Claude 2**                                                                            | Excellent, long context, multi document, fast model.                                                                                                                     |
| **Perplexity**                                                                          | The login is finnicky - login to Google on any of the other chats, and then reload (cmd+R) - it'll auto login. Hopefully they make it more intuitive/reliable in future. |
| **Bing**                                                                                | Microsoft's best. [It's not the same as GPT-4!](https://twitter.com/jeremyphoward/status/1666593682676662272?s=20). We could use help normalizing its styling.           |
| Bard                                                                                    | Google's best. [Bard's updates are... flaky](https://twitter.com/swyx/status/1678495067663925248)                                                                        |
| Llama2 via Perplexity                                                                   | Simple model host. Can run [the latest CodeLlama 34B model](https://twitter.com/swyx/status/1694870138984747449?s=20)! try it!                                           |
| Llama2 via Lepton.ai                                                                    | Simple model host. Is very [fast](https://twitter.com/rauchg/status/1692638409230094644)                                                                                 |
| Quora Poe                                                                               | Great at answering general knowledge questions                                                                                                                           |
| Inflection Pi                                                                           | Very unique long-memory clean conversation style                                                                                                                         |
| You.com Chat                                                                            | great search + chat answers, one of the first                                                                                                                            |
| HuggingChat                                                                             | Simple model host. Offers Llama2, OpenAssistant                                                                                                                          |
| Vercel Chat                                                                             | Simple open source chat wrapper for GPT3 API                                                                                                                             |
| Local/GGML Models (via [OobaBooga](https://github.com/oobabooga/text-generation-webui)) | Requires Local Setup, see oobabooga docs                                                                                                                                 |
| Phind                                                                                   | Developer focused chat with [finetuned CodeLlama](https://www.phind.com/blog/code-llama-beats-gpt4)                                                                      |
| Stable Chat                                                                             | Chat interface for [Stable Beluga](https://stability.ai/blog/stable-beluga-large-instruction-fine-tuned-models), an open LLM by Stability AI.                            |
| [OpenRouter](https://openrouter.ai)                                                     | Access GPT4, Claude, PaLM, and open source models                                                                                                                        |
| OpenAssistant                                                                           | Coming Soon — [Submit a PR](https://github.com/smol-ai/GodMode/issues/37)!                                                                                               |
| Claude 1                                                                                | Requires Beta Access                                                                                                                                                     |
| ... What Else?                                                                          | [Submit a New Issue](https://github.com/smol-ai/GodMode/issues)!                                                                                                         |

## Features and Usage

- **Keyboard Shortcuts**:

  - Use `Cmd+Shift+G` for quick open and `Cmd+Enter` to submit.
  - Customize these shortcuts (thanks [@davej](https://github.com/smol-ai/GodMode/pull/85)!):
    - Quick Open
      - ![image](https://github.com/davej/smol-ai-menubar/assets/6764957/3a6d0a16-7f54-43e5-9060-ec7b2486d32d)
    - Submit can be toggled to use `Enter` (faster for quick chat replies) vs `Cmd+Enter` (easier to enter multiline prompts)
  - `Cmd+Shift+L` to toggle light/dark mode (not customizable for now)
  - Remember you can customize further by building from source!

- **Pane Resizing and Rearranging**:

  - Resize the panes by clicking and dragging.
  - Use `Cmd+1/2/3` to pop out individual webviews
  - Use `Cmd +/-` to zoom in/out globally
  - open up the panel on the bottom right to reorder panes or reset them to default
  - `Cmd p` to pin/unpin the window Always on Top

- **Model Toggle**:

  - Enable/disable providers by accessing the context menu. The choice is saved for future sessions.
  - Supported models: ChatGPT, Bing, Bard, Claude 1/2, and more (see Supported LLM Providers above)

- **Support for oobabooga/text-generation-webui**:

  - Initial support for [oobabooga/text-generation-webui](https://github.com/oobabooga/text-generation-webui) has been added.
  - Users need to follow the process outlined in the text-generation-webui repository, including downloading models (e.g. [LLaMa-13B-GGML](https://huggingface.co/TheBloke/LLaMa-13B-GGML/blob/main/llama-13b.ggmlv3.q4_0.bin), or [GPT4-x-alpaca](https://www.youtube.com/watch?v=nVC9D9fRyNU)).
  - Run the model on `http://127.0.0.1:7860/` before running it inside of the smol GodMode browser.
  - The UI only supports one kind of prompt template. Contributions are welcome to make the templating customizable (see the Oobabooga.js provider).

- **Starting New Conversations**:

  - Use `Cmd+R` to start a new conversation with a simple window refresh.

- **Prompt Critic**: Uses Llama 2 to improve your prompting when you want it!

## video demo

- original version https://youtu.be/jrlxT1K4LEU
- Jun 1 version https://youtu.be/ThfFFgG-AzE
- https://twitter.com/swyx/status/1658403625717338112
- https://twitter.com/swyx/status/1663290955804360728?s=20
- July 11 version https://twitter.com/swyx/status/1678944036135260160
- Aug 19 godmode rewrite https://twitter.com/swyx/status/1692988634364871032

## Download and Setup

You can:

- download the precompiled binaries: https://github.com/smol-ai/GodMode/releases/latest (sometimes Apple/Windows marks these as untrusted/damaged, just open them up in Applications and right-click-open to run it).
  - for Macs, you can use the "-universal.dmg" versions and it will choose between Apple Silicon/Intel architectures. We recommend installing this, but just fyi:
    - Apple Silicon M1/M2 macs use the "arm64" version
    - Intel Macs use the ".dmg" versions with no "arm64"
  - for Windows, use ".exe" version. It will be marked as untrusted for now as we haven't done Windows codesigning yet
  - for Linux, use ".AppImage".
  - for Arch Linux, there is a [third party](https://github.com/smol-ai/GodMode/issues/47) AUR package: aur.archlinux.org/packages/godmode
- Or run it from source (instructions below)

When you first run the app:

1. log into your Google account (once you log into your google account for chatgpt, you'l also be logged in to Bard, Perplexity, Anthropic, etc). logging into Google via Anthropic Claude first seems to be the most reliable right now while we figure it out
2. For Bing, after you log in to your Microsoft account, you'll need to refresh to get into the Bing Chat screen. It's a little finnicky at first try but it works.

Optional: You can have GodMode start up automatically on login - just go to Settings and toggle it on. Thanks [@leeknowlton](https://github.com/smol-ai/GodMode/pull/188)!

![image](https://github.com/smol-ai/GodMode/assets/6764957/99c3426f-d306-469c-98fb-88c80fb12a41)

## seeking contributors!

please see https://github.com/smol-ai/GodMode/blob/main/CONTRIBUTING.md

## build from source

If you want to build from source, you will need to clone the repo and open the project folder:

1. Clone the repository and navigate to the project folder:

   ```bash
   git clone https://github.com/smol-ai/GodMode.git
   cd GodMode
   npm install --force
   npm run start # to run in development, locally
   ```

   To build your own installable Mac app (unsigned, current architecture only —
   no Apple developer account needed):

   ```bash
   npm run package-mac-local
   # output: release/build/GodMode-<version>-arm64.dmg (or x64 on Intel)
   ```

2. Generate binaries:

   ```bash
   npm run package # https://electron-react-boilerplate.js.org/docs/packaging
   # ts-node scripts/clean.js dist clears the webpackPaths.distPath, webpackPaths.buildPath, webpackPaths.dllPath
   # npm run build outputs to /release/app/dist/main
   # electron-builder build --publish never builds and code signs the app.

   # this is mostly for swyx to publish the official codesigned and notarized releases
   ```

   The outputs will be located in the `/release/build` directory.

## Related project

I only later heard about https://github.com/sunner/ChatALL which is cool but I think defaulting to a menbuar/webview experience is better - you get to use full features like Code Interpreter and Claude 2 file upload when they come out, without waiting for API
