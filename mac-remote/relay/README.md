# Mac Remote relay

Your Mac sits behind a home router, so a phone on LTE cannot reach it directly. This relay is a small Node
server that you run on any machine with a public address. The Mac dials **out** to it over a WebSocket, and
the relay forwards each request from the phone through that socket. No port forwarding, works behind CGNAT,
and the phone app gets a stable HTTPS URL you can add to the home screen.

```
phone ──HTTPS──▶ relay (public) ◀──WebSocket (outbound)── Mac mini (server.js)
```

The relay is ~200 lines, has no dependencies, and forwards bytes; it does not understand the API.
Whoever runs the relay can see the traffic, so run it yourself.

## 1. Deploy the relay

Pick one. Each takes about five minutes.

### Fly.io (always‑on, about $2–4/month for one shared‑cpu machine)

```bash
brew install flyctl && fly auth signup
cd ~/godmode/mac-remote
fly launch --copy-config --no-deploy --name <pick-a-unique-name> --region lax   # or ord / lhr / syd…
fly secrets set RELAY_SECRET="$(openssl rand -base64 24)"
fly deploy --ha=false
fly secrets list      # confirm it is set; to read it back: fly ssh console -C 'printenv RELAY_SECRET'
```

`--ha=false` matters: Fly otherwise creates two machines, and the Mac can only be attached to one of them,
so half of the phone's requests would land on an empty relay. If you already deployed without it, run
`fly scale count 1`. Your relay URL is `https://<name>.fly.dev`.

### Any VPS with Docker (Hetzner, DigitalOcean, Oracle Cloud free ARM VM…)

```bash
git clone https://github.com/henrythebozo/godmode.git && cd godmode && git checkout gh-pages && cd mac-remote
docker build -t mac-remote-relay .
docker run -d --restart unless-stopped --name relay -e RELAY_SECRET="$(openssl rand -base64 24)" -p 127.0.0.1:8080:8080 mac-remote-relay
docker exec relay printenv RELAY_SECRET     # keep this
```

Then put HTTPS in front of it with a domain you own. Caddy does that in one line:

```bash
sudo caddy reverse-proxy --from relay.yourdomain.com --to 127.0.0.1:8080
```

Without Docker: `RELAY_SECRET=… PORT=8080 node relay/relay.js` under systemd works the same.

### Render.com

Dashboard → New → Blueprint → this repo, and it picks up `render.yaml` (root dir `mac-remote`). Copy the
generated `RELAY_SECRET` from the service's Environment tab. The free plan sleeps when idle; use Starter.

## 2. Point the Mac at it

On the Mac mini:

```bash
node ~/godmode/mac-remote/server.js --relay wss://<your-relay-host> "<RELAY_SECRET>"
launchctl kickstart -k gui/$(id -u)/com.macremote.agent
tail -n 20 ~/.mac-remote/server.log      # expect: relay: connected to wss://…
```

`https://<your-relay-host>/relay/status` shows `"agent": {"name": "…"}` when the Mac is connected.

## 3. Install on the phone

Open `https://<your-relay-host>` on the phone. Log in once by scanning the QR code from
`tail -n 40 ~/.mac-remote/server.log` (or paste the token). Then:

* **iPhone**: Safari → Share → *Add to Home Screen*.
* **Android**: Chrome → ⋮ → *Add to Home screen* / *Install app*.

It opens full‑screen as **Mac Remote** and keeps you logged in for 30 days. When the Mac is asleep the app shows
its own "Your Mac is unreachable" panel and retries every 5 s (the relay serves a plain "Your Mac is offline" page
only to a browser that has never loaded the app before).

## Security notes

* The Mac authenticates to the relay with `RELAY_SECRET`. Nobody else can register as your Mac.
* The phone authenticates to the Mac with the access token, exactly as on the LAN. The relay never checks it,
  so a stranger who finds your relay URL only sees the login page and gets locked out after 5 wrong tokens.
* TLS: phone → relay is HTTPS (the platform or Caddy terminates it). Mac → relay is `wss://`. The relay
  process itself sees plaintext; that is why you host it.
* `TRUST_PROXY` tells the relay how to learn the phone's IP (used only to key the Mac's login lockout):
  `1` (default) takes the last hop of `X-Forwarded-For`, which is right behind one proxy you run (Caddy, nginx);
  `fly` uses `Fly-Client-IP` (set by `fly.toml`); `render` uses `True-Client-IP`/`CF-Connecting-IP` or the first
  `X-Forwarded-For` entry (set by `render.yaml`; also right behind Cloudflare); `0` uses the TCP peer address for a
  relay exposed directly. `CLIENT_IP_HEADER=<header>` overrides all of that for other hosts. A wrong setting cannot
  let anyone in; it only makes the 5‑try lockout key on the wrong address, which lets a stranger lock you out of
  *new* logins for 10 minutes at a time (existing sessions keep working).
* Rotate: `fly secrets set RELAY_SECRET=…` (or restart the container with a new value), then re-run
  `--relay` on the Mac.

## Limits

* One Mac per relay, and one relay process: the Mac's tunnel lives in that process's memory, so never scale the
  relay to more than one instance (`fly deploy --ha=false`, `numInstances: 1` on Render). A second Mac connecting
  with the same secret replaces the first.
* Request and response bodies are streamed in 64 KB chunks with flow control, so memory stays flat on both
  sides no matter how large the file is; a single body is capped at `MAX_BODY_MB` (512 MB) and that one
  request gets a 413/502 without affecting anything else.
* At most `MAX_PENDING` (64) requests in flight; extra ones get a 503 "Relay busy" page.
* The Mac has 90 s to start answering and 90 s between body chunks, after which the phone gets a 504.
* The phone's requests are buffered by nobody but the relay's socket buffers; the Mac never sees more than
  8 chunks ahead of what the phone has already received.
