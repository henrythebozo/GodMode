# Mac Remote

Control your Mac mini from your phone's browser, from anywhere.
One Node.js file on the Mac, zero npm dependencies, a phone-sized web app you can add to your home screen.

| Tab | What you get |
| --- | --- |
| **Screen** | Live screenshots (0.5–2 s), tap to click, double‑tap, hold for right‑click, swipe to scroll, drag mode, fullscreen |
| **Keys** | Type text, Return/Esc/Tab/arrows/F‑keys, sticky ⌘⇧⌃⌥ modifiers, common shortcuts (⌘Space, ⌘Tab, ⌘Q…) |
| **Control** | CPU/RAM/disk, volume + mute, play/pause/next (Spotify, Music, TV), lock, sleep, wake display, restart, shut down, running apps (focus/quit), open app or URL, clipboard both ways, make the Mac speak or show a notification |
| **Shell** | Run any command in `zsh -lc` with history |
| **Files** | Browse your home folder, open/download/delete files, upload from the phone, new folder |

## Honest framing before you install this

* If all you want is to *see and use the Mac's desktop*, a purpose‑built remote desktop will beat this: **Tailscale + macOS Screen Sharing** (Screens or Jump Desktop on iPhone) or **RustDesk** give you a real 30–60 fps video stream, audio, and pinch‑zoom. This app shows ~1 screenshot per second. I'd rate the "screen" part 6/10 next to those.
* What those tools *don't* give you, and this does, is a **control panel**: one tap to lock, sleep, wake, change volume, skip a track, run a shell command, grab a file, push text to the clipboard, or make the Mac talk. For that use‑case this is 8–9/10 and much lighter than a full VNC session on LTE.
* Whoever has your token has your Mac. Read the security section.

## Install (on the Mac mini)

```bash
git clone https://github.com/henrythebozo/godmode.git
cd godmode/mac-remote
bash install.sh
```

The installer checks Node 18+, offers to `brew install cliclick` (better mouse control) and `qrencode` (prints a QR code to log the phone in), generates your access token, and installs a LaunchAgent so the server starts at login and restarts if it crashes. Logs go to `~/.mac-remote/server.log`.

Then, **one time**, grant permissions in System Settings → Privacy & Security:

* **Screen Recording** → add the `node` binary the installer printed (e.g. `/opt/homebrew/bin/node`). Needed for screenshots.
* **Accessibility** → add the same `node` binary. Needed for mouse and keyboard.

In the file picker press ⌘⇧G and paste the path. Restart the server afterwards:

```bash
launchctl kickstart -k gui/$(id -u)/com.macremote.agent
```

Without the LaunchAgent you can also just run `node server.js` in a Terminal window; then grant the permissions to **Terminal** instead of `node`.

## Reach it from anywhere

The server listens on port 7331 on all interfaces. Do **not** port‑forward that on your router. Use one of these instead:

### Option A — your own relay (all code in this repo)

`relay/relay.js` is a ~200‑line, zero‑dependency server you host on any public machine (Fly.io, a $5 VPS, Render).
The Mac dials out to it, so nothing on your router changes, and the phone gets a stable HTTPS URL to install as an app.
Full steps in [relay/README.md](relay/README.md). Short version:

```bash
# on the relay host (Fly.io shown)
cd mac-remote && fly launch --copy-config --no-deploy --name my-mac-relay && fly secrets set RELAY_SECRET="$(openssl rand -base64 24)" && fly deploy --ha=false
# on the Mac
node server.js --relay wss://my-mac-relay.fly.dev "<RELAY_SECRET>" && launchctl kickstart -k gui/$(id -u)/com.macremote.agent
# on the phone: open https://my-mac-relay.fly.dev, scan the QR from ~/.mac-remote/server.log, Add to Home Screen
```

### Option B — Tailscale (free, but third‑party software on both devices)

1. Install Tailscale on the Mac and on your phone, sign in with the same account.
2. On the phone open `http://<mac-tailscale-ip>:7331` (or `http://<mac-name>:7331` with MagicDNS). Find the IP with `tailscale ip -4` or in the Tailscale app.
3. `tail -n 30 ~/.mac-remote/server.log` shows a login URL containing the token (and a QR code if `qrencode` is installed). Open it on the phone once and it stays logged in for 30 days.
4. Optional HTTPS with a real certificate: `tailscale serve --bg 7331`, then use `https://<mac-name>.<tailnet>.ts.net`.

Tailscale is a WireGuard mesh: traffic is end‑to‑end encrypted and nothing is exposed to the public internet.

### Option C — Cloudflare Tunnel

If you need a public hostname (no app on the phone), run `cloudflared tunnel --url http://localhost:7331` or a named tunnel, and put **Cloudflare Access** in front of it so the token is not the only lock.

### Add to home screen

iPhone: Safari → Share → *Add to Home Screen*. Android: Chrome → ⋮ → *Install app*. It installs as a standalone app called **Mac Remote** with its own icon; the cookie login carries over. A service worker keeps the app shell cached, so when the Mac is asleep or the relay is unreachable the app opens to its own "unreachable, retrying" panel rather than a browser error, and recovers on its own. Files open in an in‑app viewer and downloads are saved through the app, so it never navigates away from itself. Use the relay's HTTPS URL for this so the address never changes.

## Keep the Mac reachable

A sleeping Mac cannot be reached over the network and Tailscale cannot wake it. On the Mac:

```bash
sudo pmset -a sleep 0 disksleep 0 womp 1
```

Display sleep is fine; the app has a **Wake display** button (screenshots of a sleeping display are black).

## Security model

* One random 32‑character token in `~/.mac-remote/config.json` (`node server.js --token` to show, `--rotate` to invalidate every phone).
* Login sets an `HttpOnly; SameSite=Strict` cookie for 30 days. Scripts and API clients can also send `Authorization: Bearer <token>`.
* 5 wrong tokens from one IP → 10 minute lockout. Constant‑time comparison.
* Cookie‑authenticated state changes must come from the app's own origin (Origin header check).
* Files API is confined to `filesRoot` (default: your home folder). Static files are served only from `public/`.
* Files you open from the phone are shown as data (text goes into a read‑only pane, media into a player, PDFs into an isolated viewer); an HTML file in your home folder is displayed as source and can never run as part of the app. Downloads carry a `Content-Security-Policy: sandbox` header for the same reason.
* Restart/shutdown need an explicit confirm and can be disabled with `"allowPowerOff": false`; the shell can be disabled with `"allowShell": false`.
* Plain HTTP by default. Over Tailscale that is already encrypted. On any other network set `"tls": { "cert": "...", "key": "..." }` in the config or use `tailscale serve`.

What this does **not** protect you from: someone who gets the token, or someone who already has your Mac's user session. The server runs as you and can do anything you can.

## Config

`~/.mac-remote/config.json` (created on first run):

```json
{
  "token": "…",
  "port": 7331,
  "host": "0.0.0.0",
  "filesRoot": "/Users/you",
  "allowShell": true,
  "allowPowerOff": true,
  "tls": null,
  "relay": null
}
```

`relay` is set by `node server.js --relay wss://host secret` and cleared by `--no-relay`. Relayed requests are replayed through a
separate loopback‑only listener, so `host` and `tls` only affect direct (LAN/Tailscale) access and can be combined with the relay freely.

Set `"host": "100.x.y.z"` (your Tailscale IP) to refuse connections from the LAN entirely.

## API

Everything is JSON under `/api/`. Coordinates are 0–1 fractions of the screen so the phone never needs to know the resolution.

```
POST /api/login            {token}
GET  /api/status
GET  /api/screen.jpg?w=1280&q=60
POST /api/mouse            {action: click|dblclick|rightclick|move|drag|scroll, x, y, x2, y2, dx, dy}
POST /api/key              {key: "return"|"escape"|"a"…, mods: ["cmd","shift","ctrl","alt"]}
POST /api/type             {text}
GET/POST /api/volume       {level 0-100} | {muted: bool}
POST /api/media            {action: playpause|next|prev}
POST /api/power            {action: lock|sleep|displaysleep|wake|restart|shutdown, confirm}
GET/POST /api/apps         {action: open|focus|quit, name}
POST /api/open             {url}
GET/POST /api/clipboard    {text}
POST /api/say              {text, voice}
POST /api/notify           {title, body}
POST /api/shell            {cmd, cwd, timeout}
GET  /api/files?path=      GET /api/files/download?path=   POST /api/files/upload?path=&name=
POST /api/files/mkdir      POST /api/files/delete          POST /api/logout
```

Example from any computer on your tailnet:

```bash
curl -H "Authorization: Bearer $TOKEN" -X POST -H 'Content-Type: application/json' \
  -d '{"text":"dinner is ready"}' http://mac-mini:7331/api/say
```

## How it works

* `server.js` — HTTP server, auth, sessions, static files. Node built‑ins only.
* `lib/mac.js` — every macOS action shells out to something Apple ships: `screencapture` + `sips` for the screen, `osascript` (AppleScript and JXA with the CoreGraphics bridge) for keys, mouse fallback, volume, apps, power; `pbcopy`/`pbpaste`, `pmset`, `caffeinate`, `open`, `say`. `cliclick` is used for the mouse when installed because it is more battle‑tested than the JXA fallback.
* `lib/ws.js` — a small RFC 6455 WebSocket implementation (server and client) shared by the relay and the Mac, tested against the reference `ws` package.
* `relay/relay.js` — the public relay: accepts the Mac's outbound WebSocket and streams every phone request through it (chunked, flow‑controlled, so a 2 GB download costs neither side any memory). `Dockerfile`, `fly.toml` and `render.yaml` deploy it.
* `public/` — the phone UI. Plain HTML/CSS/JS, no build step, installable as a PWA (`sw.js` caches the shell).
* `tools/make-icons.js` — draws the icon PNGs with a 60‑line PNG encoder so there is still no dependency.

## Troubleshooting

* **"screencapture failed"** → Screen Recording permission for `node` (or Terminal), then restart the server.
* **Taps do nothing / "not permitted"** → Accessibility permission for `node`. Check `tail ~/.mac-remote/server.log`.
* **Media buttons don't work** → they script Spotify/Music/TV/Podcasts. For a browser tab use ⌘ shortcuts or the Screen tab.
* **Screen is black** → display asleep. Tap *Wake display*.
* **"Your Mac is offline" on the relay URL** → the Mac is asleep or its relay client can't connect. On the Mac: `tail ~/.mac-remote/server.log` (look for `relay: connected` or `rejected our secret`) and `curl https://<relay>/relay/status`.
* **Can't connect from LTE with Tailscale** → Tailscale not running on one side, or the Mac is asleep.
* **Run in the foreground for debugging**: `launchctl bootout gui/$(id -u)/com.macremote.agent; node server.js`.

## Uninstall

```bash
launchctl bootout gui/$(id -u)/com.macremote.agent
rm ~/Library/LaunchAgents/com.macremote.agent.plist
rm -rf ~/.mac-remote   # token, sessions, log
```
