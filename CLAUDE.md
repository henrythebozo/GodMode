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
- **The key shapes** (`KEY_SHAPES` / `identifyKey` / `keyArticle`, in
  `cli/lib/config.mjs` and in the page's paste-detection block). Four regexes
  whose *order* is load-bearing: `sk-ant-` and `sk-or-` also match the generic
  `sk-`, so the specific ones must be tried first. `keys.mjs` in the scratchpad
  asserts the two copies are byte-identical by extracting them from the HTML.

When you change one, change the other, and say so in the commit. The tests
that would catch a drift are `cli.mjs` and `vault.js` in the scratchpad.

Four rules the vault design rests on, all learned the hard way:

1. **Links live in the prose and nowhere else.** They are parsed out of the
   body on every read. Storing them alongside means two copies and the first
   edit through Obsidian or an editor desyncs them.
2. **Timestamps come from mtime, not from frontmatter.** `updated:` records
   when *Jarvis* last wrote the file. Obsidian, vim and everything else change
   the body and leave frontmatter alone, so an edit made anywhere else is
   invisible to it — which is how the folder sync came to overwrite real
   Obsidian edits with the app's stale copy, and how `mem list --newest` came
   to ignore them. Both sides now take `max(Date.parse(updated), mtime)`.
3. **Sync needs three inputs, not two.** With only "here" and "there", a note
   missing from one side cannot be told apart from a note that is new on the
   other, so the safe reading is always "new" and nothing can ever be deleted.
   `store.vaultSynced` holds the titles both sides agreed on at the end of the
   last successful sync. It is written only after the write pass finishes —
   recording it earlier would make a half-written vault's missing half look
   deleted next time — and cleared when the folder is disconnected, so the
   first sync with the *next* folder cannot delete for non-membership.
4. **A `[[link]]` resolves by TITLE only.** There is a separate loose search
   for what a person or model typed, which may fall back to matching a body.
   Using the loose one for link resolution makes every unwritten link "resolve"
   to the note that mentions it, and unresolved nodes silently vanish from the
   graph.

## Syncing the vault: git, not a server

`cli/lib/git.mjs` shells out to the real `git` rather than reimplementing any
of it. Two things there are deliberate and worth keeping:

- **A conflict keeps both notes.** Git's default is `<<<<<<<` markers in the
  file, which for a note means a mangled body and — if the clash reaches the
  top — frontmatter that no longer parses. Instead `theirs` becomes
  `Name (conflict).md`, *retitled in its frontmatter too*, so it is a distinct
  node in the graph rather than a second ambiguous `[[Name]]`. An edit always
  beats a deletion: the edit is the newer intent and the deletion costs one
  keystroke to repeat.
- **Push scans for keys first**, reusing `identifyKey` from `config.mjs`. It
  asks `git ls-files -co --exclude-standard` once for the exact set git would
  take — walking the tree and running `check-ignore` per file is a subprocess
  per note, and an ignored file cannot leak anyway.

`vault init` **refuses** inside Dropbox / iCloud / OneDrive and the rest, but
only warns once the repository exists — refusing then would strand someone
mid-sync, and the warning stays true until they move it. Detection resolves
symlinks first (`~/jarvis-vault` pointing into iCloud looks innocent from the
path), and walks up to the nearest existing ancestor because the vault may not
exist yet at init. The pattern list is deliberately conservative: a false
positive blocks a fine setup and teaches people to reach for `--allow-cloud`,
so a folder merely *called* `Sync` or `Box` does not count.

`initRepo` forces the branch to `main` **only on a repo it just created**.
Renaming the branch of a folder somebody already had in git would strand their
history on the old branch and push an empty `main` over the top of it.

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

The closest thing for the other two is a key that costs one paste, and two
things were deliberately **not** done to get there:

- **Never `navigator.clipboard.readText()`.** It would let the page look at
  whatever you had copied, unasked, to save one keystroke. The paste handler
  only ever reacts to a paste the person performed, and asks before saving.
- **Never reuse `CLAUDE_CODE_OAUTH_TOKEN`.** That token is issued to
  Anthropic's own client for Claude Code; presenting it from a different
  application is outside what it was issued for, and a subscription is not a
  licence to route another app through it.

Two smaller rules the paste handler rests on: `preventDefault()` is what keeps
the key out of the box, so the field is **not** cleared as well (that would
destroy a half-written message on top of everything else); and a declined save
says so, because a paste that vanishes with no explanation is a mystery.

On the CLI side, `saveConfig` deliberately refuses to write back a key that
came from the environment — turning a per-shell secret into a stored one behind
someone's back is wrong. `jarvis key import` is the *only* caller allowed to
opt out (via `persistEnvKeys`), because storing it is the entire point of that
command and the person typed it. Any new command that needs the same exemption
almost certainly does not.

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

**`hidden` loses to any author rule that sets `display`.** It is `display:none`
from the UA stylesheet, so `.composer button { display: grid }` beat it and the
stop button sat in the composer permanently — while `el.hidden` was `true` and
every test that read the property passed. Three elements were visible this way
and none of the ~600 assertions caught it; a screenshot did. There is now a
global `[hidden] { display: none !important }` and `hiddencheck.js`, which
opens every dialog and asserts that nothing carrying the attribute has a
computed display other than none. Prefer that check to adding `.hidden`
assertions one at a time.

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
