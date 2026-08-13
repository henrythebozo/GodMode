# Jarvis Home Screen widget — setup

`JarvisWidget.swift` in this folder is a complete, ready-to-use WidgetKit
widget (next reminder + next calendar event, reading a snapshot the main app
already writes for it — see below). It's **staged here rather than wired
into `App.xcodeproj`**: creating a new widget-extension target means adding
a second app target, its own Info.plist, an App Group entitlement, and an
embed-extension build phase — real Xcode-project surgery that Xcode's own
"New Target" wizard does correctly and that I didn't think was safe to
hand-edit into the `.pbxproj` blind, without Xcode here to catch a mistake.
Everything else the widget depends on **is** already wired in and working:
`JarvisWidgetBridge.swift` (native) and `syncWidgetSnapshot()` in
`www/index.html` (JS) keep a small snapshot of "what's next" flowing into a
shared App Group container whenever the dashboard's Upcoming list updates.

## One-time setup, in Xcode (about 5 minutes)

1. With `ios/App/App.xcworkspace` open, **File → New → Target… → Widget
   Extension**. Name it `JarvisWidget`. Un-check "Include Configuration
   Intent" (this widget doesn't need one). Finish, and let Xcode add it.
2. Xcode generates a starter Swift file for the new target (something like
   `JarvisWidget/JarvisWidget.swift`) — **delete its contents and paste in
   this folder's `JarvisWidget.swift` instead.** Everything it needs
   (`WidgetKit`, `SwiftUI`) is already imported.
3. **Add the App Group capability to both targets:**
   - Select the **App** target → **Signing & Capabilities** → **+
     Capability** → **App Groups** → **+** → enter
     `group.com.henrythebozo.jarvis` (must match exactly — it's hardcoded
     in both `JarvisWidgetBridge.swift` and `JarvisWidget.swift`). If Xcode
     asks about an entitlements file, either let it generate one or point
     it at `App/App/App.entitlements`, which already has this key set.
   - Select the **JarvisWidget** target → **Signing & Capabilities** → add
     the same App Groups capability with the same group ID.
   - Set a **Team** on the JarvisWidget target too (Automatic signing), the
     same way you already did for App.
4. Run the app once on a device/simulator so it writes its first snapshot
   (add a reminder, or open Settings → Calendar and sync one), then add the
   widget from the Home Screen's "+" widget picker, under Jarvis.

## Why the App Group and not something simpler

A widget extension runs in its own process, sandboxed separately from the
main app — it can't read the WKWebView's `localStorage`, which is where all
of Jarvis's actual data lives. An App Group is Apple's mechanism for two
targets from the same developer to share a small UserDefaults container;
`JarvisWidgetBridge.swift` is the only thing that writes to it (from a
`WKScriptMessageHandler`, driven by the JS side — no separate Capacitor
plugin needed), and the widget only reads from it. Nothing else about
Jarvis's BYOK architecture changes: API keys and everything else stay in
`localStorage`, never touch the shared container, and the widget never talks
to any AI provider itself — it just displays what the main app last synced.

## If the widget doesn't seem to update

Timelines only refresh at the time embedded in the last synced entry (or
after an hour, as a fallback) — it's not pushed live. Backgrounding and
reopening the app calls `syncWidgetSnapshot()` again and asks WidgetKit to
reload, which should catch up right away.
