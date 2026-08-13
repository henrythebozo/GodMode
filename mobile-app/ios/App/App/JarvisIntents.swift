import AppIntents
import Capacitor
import UIKit

/*
 Siri Shortcuts, via App Intents (iOS 16+) — not SiriKit's older
 Intents.intentdefinition mechanism, which needs its own extension target.
 App Intents just needs Swift types conforming to these protocols; the OS
 discovers them automatically at build time.

 These intents don't reimplement any of Jarvis's logic natively — that all
 still lives in the JS running inside the WKWebView (memory, tools, the AI
 call itself). Each intent's only job is: ask iOS to bring the app to the
 foreground (`openAppWhenRun`), wait for the web app to finish booting, then
 call a small JS hook (`window.jarvisSiriAsk` / `window.jarvisSiriRemind`,
 defined in www/index.html) that feeds straight into the same
 submitCommand()/toolSetReminder() code paths the on-screen mic and
 keyboard already use.
*/

/// Polls for the Capacitor bridge's WKWebView and, once the page has
/// finished its own boot sequence, runs `js` in it. Retries on a short
/// timer rather than assuming a fixed delay, since "app was already
/// running" and "cold launch" take very different amounts of time.
private func runInJarvisWebView(_ js: String, retriesLeft: Int = 25) {
	DispatchQueue.main.async {
		guard
			let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
				?? UIApplication.shared.connectedScenes.first as? UIWindowScene,
			let window = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first,
			let bridgeVC = window.rootViewController as? CAPBridgeViewController,
			let webView = bridgeVC.bridge?.webView
		else {
			if retriesLeft > 0 {
				DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { runInJarvisWebView(js, retriesLeft: retriesLeft - 1) }
			}
			return
		}
		JarvisWidgetBridge.shared.register(on: webView) // cheap no-op after the first successful call; piggybacked here since this is the one place that reliably finds the webView
		webView.evaluateJavaScript("typeof window.jarvisSiriReady === 'function' && window.jarvisSiriReady()") { result, _ in
			if (result as? Bool) == true {
				webView.evaluateJavaScript(js, completionHandler: nil)
			} else if retriesLeft > 0 {
				DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { runInJarvisWebView(js, retriesLeft: retriesLeft - 1) }
			}
		}
	}
}

/// Swift → JS string literal, via JSONEncoder (handles quotes/newlines/unicode correctly).
private func jsStringLiteral(_ s: String) -> String {
	(try? String(data: JSONEncoder().encode(s), encoding: .utf8)) ?? "\"\""
}

@available(iOS 16.0, *)
struct AskJarvisIntent: AppIntent {
	static var title: LocalizedStringResource = "Ask Jarvis"
	static var description = IntentDescription("Ask Jarvis a question or give it a command, out loud through Siri.")
	static var openAppWhenRun: Bool = true

	@Parameter(title: "Question")
	var question: String

	func perform() async throws -> some IntentResult {
		runInJarvisWebView("window.jarvisSiriAsk(\(jsStringLiteral(question)))")
		return .result()
	}
}

@available(iOS 16.0, *)
struct SetJarvisReminderIntent: AppIntent {
	static var title: LocalizedStringResource = "Set a Jarvis Reminder"
	static var description = IntentDescription("Ask Jarvis to remind you of something, a number of minutes from now.")
	static var openAppWhenRun: Bool = true

	@Parameter(title: "Reminder text")
	var text: String

	@Parameter(title: "Minutes from now")
	var minutes: Int

	func perform() async throws -> some IntentResult {
		runInJarvisWebView("window.jarvisSiriRemind(\(jsStringLiteral(text)), \(minutes))")
		return .result()
	}
}

@available(iOS 16.0, *)
struct JarvisShortcuts: AppShortcutsProvider {
	static var appShortcuts: [AppShortcut] {
		AppShortcut(
			intent: AskJarvisIntent(),
			phrases: [
				"Ask \(.applicationName) \(\.$question)",
				"Ask \(.applicationName)",
			],
			shortTitle: "Ask Jarvis",
			systemImageName: "waveform.circle"
		)
		AppShortcut(
			intent: SetJarvisReminderIntent(),
			phrases: [
				"Set a reminder with \(.applicationName)",
				"\(.applicationName), remind me",
			],
			shortTitle: "Set a Reminder",
			systemImageName: "bell.badge"
		)
	}
}
