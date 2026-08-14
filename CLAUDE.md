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
