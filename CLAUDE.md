# Working on this repo

## `docs/jarvis.html` and `mobile-app/www/index.html`

These are meant to stay in sync. `mobile-app/www/index.html` is a fork of
`docs/jarvis.html` with a layer of native-only additions (Capacitor speech
recognition, local notifications, Siri Shortcuts bridge, Home Screen widget
bridge). When you change `docs/jarvis.html`:

1. `git diff HEAD -- docs/jarvis.html` to capture the change as a patch.
2. Retarget it at the mobile file and try applying it with fuzzy matching:
   `patch -p1 --fuzz=5 -d . < the-retargeted-patch`.
3. Most hunks apply cleanly since the files are structurally identical outside
   the native-only sections. Any hunk that fails is almost always because it
   landed near one of those sections — resolve it by hand, matching the
   surrounding native code's conventions.
4. Copy the result to `mobile-app/ios/App/App/public/index.html` too (the
   `npx cap sync` output, gitignored but worth keeping current so a fresh
   Xcode open isn't stale).
5. Run the same validation on both files: `node --check` on the extracted
   `<script>` content, an HTML-well-formedness pass, a duplicate-id check, a
   `getElementById`-target-exists check, and a CSS `var(--x)`-used-vs-defined
   check. None of this can be verified by actually running the app — there's
   no browser or Xcode in this environment — so static checks are what stand
   in for testing.

## `cli/` — the terminal half

`cli/` is a zero-dependency Node CLI sharing no code with `docs/jarvis.html`,
because that file is a single no-build page with no imports and a shared module
would break it. Two things are therefore **deliberate duplicates**, and both
sides have to move together:

- **The provider layer** (`cli/lib/provider.mjs` vs the `streamCompletion` /
  `parseEvent` pair in the page). Request bodies, the SSE shapes for all four
  providers, the `stream_options` self-healing retry, and the price table.
- **The vault** (`cli/lib/vault.mjs` vs the vault section in the page). Note
  shape, `[[wikilink]]` parsing, graph building, and the force layout.

When you change one, change the other, and say so in the commit. The tests
that would catch a drift are `cli.mjs` and `vault.js` in the scratchpad.

Two rules the vault design rests on, both learned the hard way:

1. **Links live in the prose and nowhere else.** They are parsed out of the
   body on every read. Storing them alongside means two copies and the first
   edit through Obsidian or an editor desyncs them.
2. **A `[[link]]` resolves by TITLE only.** There is a separate loose search
   for what a person or model typed, which may fall back to matching a body.
   Using the loose one for link resolution makes every unwritten link "resolve"
   to the note that mentions it, and unresolved nodes silently vanish from the
   graph.

## Signing in: only OpenRouter, and why

Do not go looking for "Sign in with Claude" or "Sign in with Google" again —
both were checked against the vendors' own docs and neither is available to a
third-party client here:

- **Anthropic.** The OAuth that exists is first-party. Claude Code and Claude
  Desktop authenticate a subscription against Anthropic's own registered
  clients (`claude setup-token`, `CLAUDE_CODE_OAUTH_TOKEN`); there is no public
  client registration, and a claude.ai login grants no API access at all.
- **Google.** OAuth for the Generative Language API is real but is documented
  for desktop apps holding a `client_secret.json`, and needs a Cloud project,
  an enabled API and a consent screen — strictly more setup than the AI Studio
  key it would replace, with nowhere safe for the secret in a page with no
  server.
- **OpenRouter.** PKCE, no client id, no client secret. A single-file page can
  run the whole flow. It brokers Claude, Gemini and GPT, so one sign-in reaches
  all three anyway — which is why it is the only one implemented.

PKCE fails *silently until the exchange*: a wrong `code_challenge` produces a
perfectly normal redirect and only dies at a server this environment cannot
reach. Both implementations are therefore checked against the worked example in
RFC 7636 appendix B, and the browser's challenge is compared byte-for-byte with
Node's for the same verifier. Keep those assertions.

## Testing what cannot be reached from here

No live model provider has ever been called from this environment, and a child
process cannot open a socket to a localhost mock server either (the parent
process can). So:

- The **web app's** streaming path is tested by stubbing `window.fetch` with a
  real `ReadableStream` emitting each provider's real SSE frames.
- The **CLI's** assistant path is tested in-process by stubbing `globalThis.fetch`
  and importing `cli/lib/agent.mjs` — which is why the agent logic lives in a
  module and takes an injectable `io` rather than writing to stdout directly.
- The CLI's filesystem half is tested by running the real binary as a
  subprocess, which is the only honest way to cover argument parsing.

**A top-level throw in `docs/jarvis.html` does not look like a broken page.**
Function declarations hoist, so every function stays callable while every
top-level `const` after the throw is missing and every `addEventListener` after
it was never attached — a suite of behavioural tests can pass green on a page
that is half dead. This happened for real: a `renderVaultFolder()` call placed
above the `const FS_OK` it reads hit the temporal dead zone. Assert that
evaluation reached the end (read a late const) before asserting anything else.

Two harness bugs to avoid repeating: setting `animation-delay` does not re-seek
a running animation in Chromium (`a.pause(); a.currentTime = …` does), and
`getAnimations()` includes CSS *transitions*, so freezing everything at
`currentTime = 0` rewinds in-flight colour transitions and screenshots the
pre-transition state.

## On cinematic/scroll-driven visual treatments

Jarvis is a functional single-page app (a dashboard, not a scrolling
marketing page) that's deliberately self-contained — no build step, no
external JS/CSS libraries. That's a real constraint, not a style preference:

- Don't add 3D engines (Three.js, Spline) or scroll-choreography libraries
  (GSAP ScrollTrigger) to satisfy a "cinematic site" request literally —
  they don't fit an app with no scroll-funnel structure, and pulling them in
  breaks the single-file, dependency-free architecture.
- A cinematic *moment* (see the boot intro, "Quiet Awakening") can fit —
  short, skippable, plays once, reuses the app's existing visual language
  (the orb) rather than inventing new imagery, and never blocks or delays
  real functionality (e.g. the first-run Settings prompt had to be
  re-sequenced to wait for the intro rather than racing it).
- If a future request is genuinely for a marketing/landing page (not the app
  itself), the cinematic-scroll treatment is much more appropriate there —
  but even then, treat generic "act as a film director / DP / sound
  designer" prompt templates as a menu of ideas to select from for fit, not
  a spec to implement wholesale.
