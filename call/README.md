# 📞 GodMode Call — a FaceTime-style AI assistant you can video-call

Open the app, tap **Call**, and just talk. Point your camera at something and ask
"what am I looking at?" or "how much is this worth?" — the assistant looks at a
snapshot and answers in a natural voice. Works in Safari on iPhone and Mac.

- **Voice:** [ElevenLabs Agents](https://elevenlabs.io/docs/eleven-agents) over **WebRTC** (low latency, natural barge-in interruption).
- **Vision:** your camera snapshots are sent to a vision model (**Claude** by default) **only when you ask something visual** — not streamed.
- **Secrets stay on the server.** The browser only ever receives a short-lived conversation token.
- **Nothing is recorded or saved.** Frames are sent for a single answer and discarded.

---

## ⚠️ Read this first — honest scope

- **This is not Apple FaceTime.** It's a FaceTime-*style* web app that runs its own
  call experience. It does not and cannot join Apple's FaceTime network.
- **ElevenLabs does not "see" live video.** Its documented multimodal/file input is
  for chat channels (widget, Slack, file-upload API), **not** streaming camera frames
  into a live WebRTC voice call. So vision here works by sampling a **still frame** when
  you ask a visual question and sending it to a separate vision model, then feeding the
  result back to the agent. The assistant never pretends to see continuous video.
- **Visual answers are only as good as the frame.** The vision prompt is tuned to admit
  when it can't see clearly and to ask you to move closer — rather than inventing details.

---

## Quick start (local, on your Mac)

```bash
cd call
cp .env.example .env     # then edit .env (see below)
npm install              # installs deps + builds the voice SDK bundle
npm start                # http://localhost:8787
```

Open **http://localhost:8787** on the same Mac. `localhost` is a secure context, so the
camera and mic work without HTTPS. (For your **iPhone**, see *Testing on a phone* below —
real devices require HTTPS for camera/mic.)

### What goes in `.env`

| Variable | Required? | What it's for |
|---|---|---|
| `ELEVENLABS_API_KEY` | **Yes** | Mints the WebRTC conversation token. [Get one](https://elevenlabs.io/app/settings/api-keys). |
| `ELEVENLABS_AGENT_ID` | **Yes** | Your agent. [Agents dashboard](https://elevenlabs.io/app/agents). |
| `ANTHROPIC_API_KEY` | **Yes** (for vision) | Vision (and optional price search). |
| `VISION_PROVIDER` | No | `anthropic` (default) or `openai`. |
| `VISION_MODEL` | No | Defaults to `claude-sonnet-5-5`. Use a model **your account can access** (e.g. `claude-haiku-5-5` for lower cost, or `gpt-4o` with OpenAI). |
| `OPENAI_API_KEY` | Only if `VISION_PROVIDER=openai` | Vision via OpenAI. |
| `PRICE_CHECK_ENABLED` | No | `true` turns on **paid** web search for current values. Off by default. |
| `ELEVENLABS_VOICE_ID` | No | Override the agent's voice. You can also pick in-app. |
| `SSL_CERT` / `SSL_KEY` | No | Serve HTTPS (needed for phones). |

---

## 🔧 Configure your ElevenLabs agent (important)

The app connects to **your** agent. For the full experience, set two things on the agent
in the [ElevenLabs dashboard](https://elevenlabs.io/app/agents):

### 1. System prompt — tell it how to use its eyes

Add something like this to the agent's system prompt:

```
You are a warm, concise personal assistant on a live video call. The user can point
their camera at things. You have two tools:

- analyze_camera(query): look through the user's camera and answer a visual question.
  Call this whenever the user asks about what they're seeing ("what is this?",
  "what am I looking at?", "read this label", "what colour is it?"). Pass their
  question as `query`.
- check_price(item): look up the current market value of an item via web search.
  Call this for "how much is this worth / what does it cost now?" If you need to
  know what the item is first, call analyze_camera, then check_price with the
  identified item.

If a tool says the image is unclear, ask the user to move closer, steady the camera,
or improve the lighting. Never invent what you can't see or a price you can't verify.
Keep replies short and natural — they're spoken aloud.
```

### 2. Client tools — register them so the agent can call the camera

In the agent's **Tools** settings, add two **client tools** (type: *Client*):

| Tool name | Parameter | Description |
|---|---|---|
| `analyze_camera` | `query` (string) | Look through the user's camera and answer a visual question. |
| `check_price` | `item` (string) | Look up the current market value / price of an item via web search. |

The tool **names must match exactly** — the app registers handlers with these names and
runs them in the browser (capture frame → `/api/vision`, or `/api/price-check`).

> **Don't want to touch the agent config?** The app still works. The **Look** button in
> the call always captures a frame, describes it, and prompts the assistant — even if the
> agent has no tools. Natural spoken "what am I looking at?" needs the `analyze_camera`
> tool, though.

### 3. (Optional) Allow voice overrides

To let the in-app voice picker override the agent's voice, enable **voice** overrides in
the agent's **Security** / overrides settings. Otherwise the agent's configured voice is used.

### 4. (Optional) Enable conversation events

For live captions and the speaking/listening orb, make sure the relevant events (user
transcript, agent response, etc.) are enabled in the agent's **Advanced** tab.

---

## 💸 Costs — know before you turn things on

Everything here bills to **your** accounts. Rough shape (check current pricing yourself):

- **ElevenLabs Agents** — billed per minute of conversation (plan-dependent). This runs
  for the whole call.
- **Vision (Claude/OpenAI)** — one image + text request **each time** you ask a visual
  question or tap **Look**. Small per call, but it adds up with heavy use.
- **Scene awareness (optional, off by default)** — sends a frame **every ~20s** while on.
  That's a vision call every 20s = ~3/minute. A badge shows when it's active. Keep the
  interval high; turn it off when not needed.
- **Price lookup (optional, off by default)** — uses Claude's **web_search** tool, which
  Anthropic bills **per search** on top of tokens. Only fires when you ask for a value.

The lobby and Settings show which of these are configured/enabled so nothing runs silently.

---

## Privacy & permissions

- Camera and mic are requested when you start a call. If you deny the camera, the call
  continues **voice-only** and the assistant says it can't see.
- Turning the **camera off** immediately stops all frame uploads (including scene awareness).
- A **"Looking…"** badge appears whenever a frame is being sent to the vision model.
- Ending the call stops **all** camera and microphone tracks.
- **No recordings or images are stored** — not on the server, not in the browser. Frames
  live only in memory for the duration of one request.

---

## Testing on a phone (iPhone Safari)

Real devices require **HTTPS** for camera/mic (localhost is the only exception). Two options:

1. **A tunnel** (easiest): run `npm start`, then expose it with e.g.
   `cloudflared tunnel --url http://localhost:8787` or `ngrok http 8787`, and open the
   `https://…` URL it gives you on your phone.
2. **Local HTTPS cert:** generate a cert (e.g. with [`mkcert`](https://github.com/FiloSottile/mkcert)),
   point `SSL_CERT`/`SSL_KEY` at it in `.env`, restart, and open the `https://<your-LAN-ip>:8787`
   address printed at startup.

Add to the iPhone home screen (Share → Add to Home Screen) for a full-screen, app-like feel.

---

## Using it in a call

- **Just talk** — barge in any time; WebRTC supports interrupting the assistant mid-sentence.
- **"What am I looking at?"** / **"How much is this worth?"** — the agent calls its camera/price tools.
- **Look** button — force a visual answer (works without agent tool config).
- **Mute / Camera / Flip / End** — standard controls. **Flip** switches front/rear camera.
- **Settings** (lobby) — pick a voice, set an Agent ID, toggle scene awareness.
- **Captions** — toggle to see the transcript.

---

## How it fits together

```
Browser (public/)                         Server (server.js)              Third parties
─────────────────                         ──────────────────              ─────────────
Call ─┬─ GET /api/config ───────────────▶ returns non-secret config
      ├─ GET /api/elevenlabs/token ─────▶ mint token (xi-api-key) ──────▶ ElevenLabs REST
      ├─ Conversation.startSession(webrtc, token) ───────────────────────▶ ElevenLabs WebRTC (voice)
      │     clientTools: analyze_camera, check_price
      ├─ (visual Q) capture frame ─▶ POST /api/vision ──────────────────▶ Claude / OpenAI (vision)
      └─ (price Q)  POST /api/price-check ──────────────────────────────▶ Claude + web_search
```

- Secret keys: **server only.** Browser gets a short-lived token + booleans.
- Frontend voice SDK (`@elevenlabs/client`) is bundled locally to `public/vendor/` — no runtime CDN.

## API reference (server)

| Route | Method | Purpose |
|---|---|---|
| `/api/config` | GET | Non-secret config + which services are configured. |
| `/api/elevenlabs/token` | GET | Mint a WebRTC conversation token (`?agentId=` optional). |
| `/api/voices` | GET | List your ElevenLabs voices for the picker. |
| `/api/vision` | POST | `{image, question, context}` → spoken-friendly description. |
| `/api/price-check` | POST | `{query}` → current value via web search (if enabled). |
| `/healthz` | GET | Liveness. |

## Tests

```bash
npm test
```

Offline unit + integration tests (`node --test`) covering token minting, the vision
request shape (both providers), price-check gating, the data-URI stripping, and the
**invariant that secret keys never appear in `/api/config`**. Network is mocked, so tests
spend no real credits.

## Troubleshooting

- **"Could not start the call" → NO_ELEVENLABS_KEY / NO_AGENT_ID** — fill in `.env`, restart.
- **Token 401** — bad `ELEVENLABS_API_KEY`, or the agent requires auth your key lacks.
- **Vision error about the model** — set `VISION_MODEL` to a model your account can use.
- **Camera works on Mac but not iPhone** — you're on `http://`. Use HTTPS (see above).
- **Agent never looks on its own** — it's missing the `analyze_camera` client tool; add it,
  or use the **Look** button.

## License

MIT (same as the parent repo).
