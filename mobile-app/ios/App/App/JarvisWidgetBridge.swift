import Capacitor
import UIKit
import WebKit
import WidgetKit

/// Must match the App Group capability added to both this app target and the
/// widget extension target in Xcode (Signing & Capabilities → + App Groups).
/// See mobile-app/ios/WidgetSource/README.md for the one-time setup — the
/// widget extension itself is staged there rather than wired into this
/// project blind, since creating a new Xcode target isn't something safe to
/// hand-edit into project.pbxproj without Xcode there to catch mistakes.
let jarvisAppGroupID = "group.com.henrythebozo.jarvis"

/// Bridges reminder/calendar data from the web app's localStorage (native
/// Swift has no visibility into that on its own) out to a small App Group
/// UserDefaults snapshot a Home Screen widget can read. Uses a plain
/// WKScriptMessageHandler rather than a full Capacitor plugin — no extra
/// CocoaPod/plugin registration needed, just a JS postMessage call (see
/// `syncWidgetSnapshot()` in www/index.html) that this receives natively.
final class JarvisWidgetBridge: NSObject, WKScriptMessageHandler {
	static let shared = JarvisWidgetBridge()
	private var registeredWebView: WKWebView?

	private override init() { super.init() }

	/// Finds the Capacitor bridge's webView, if the app currently has one on screen,
	/// and registers this handler on it. Safe to call repeatedly (e.g. from every
	/// applicationDidBecomeActive) — a given webView is only registered once.
	func registerIfNeeded() {
		guard
			let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
				?? UIApplication.shared.connectedScenes.first as? UIWindowScene,
			let window = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first,
			let bridgeVC = window.rootViewController as? CAPBridgeViewController,
			let webView = bridgeVC.bridge?.webView
		else { return }
		register(on: webView)
	}

	func register(on webView: WKWebView) {
		guard registeredWebView !== webView else { return }
		webView.configuration.userContentController.add(self, name: "jarvisWidgetSync")
		registeredWebView = webView
	}

	func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
		guard message.name == "jarvisWidgetSync", let dict = message.body as? [String: Any] else { return }
		guard let defaults = UserDefaults(suiteName: jarvisAppGroupID) else { return }
		defaults.set(dict["reminderText"] as? String, forKey: "nextReminderText")
		defaults.set(dict["reminderAt"] as? Double, forKey: "nextReminderAt")
		defaults.set(dict["eventText"] as? String, forKey: "nextEventText")
		defaults.set(dict["eventAt"] as? Double, forKey: "nextEventAt")
		if #available(iOS 14.0, *) { WidgetCenter.shared.reloadAllTimelines() }
	}
}
