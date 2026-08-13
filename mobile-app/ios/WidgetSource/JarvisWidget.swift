import WidgetKit
import SwiftUI

/// Home Screen widget showing the next Jarvis reminder and/or calendar event.
/// Reads a small snapshot written by the main app into a shared App Group
/// UserDefaults container — see mobile-app/ios/App/App/JarvisWidgetBridge.swift
/// for the native side and `syncWidgetSnapshot()` in www/index.html for the
/// JS side that feeds it. This file is staged rather than wired into
/// App.xcodeproj — see README.md in this folder for the one Xcode step that
/// turns it into a real widget extension target.

let jarvisAppGroupID = "group.com.henrythebozo.jarvis" // must match JarvisWidgetBridge.swift and the App Group added to both targets

struct JarvisWidgetEntry: TimelineEntry {
	let date: Date
	let reminderText: String?
	let reminderAt: Date?
	let eventText: String?
	let eventAt: Date?

	var hasAnything: Bool { reminderText != nil || eventText != nil }
}

struct JarvisWidgetProvider: TimelineProvider {
	func placeholder(in context: Context) -> JarvisWidgetEntry {
		JarvisWidgetEntry(date: Date(), reminderText: "Call the dentist", reminderAt: Date().addingTimeInterval(3600), eventText: nil, eventAt: nil)
	}

	func getSnapshot(in context: Context, completion: @escaping (JarvisWidgetEntry) -> Void) {
		completion(currentEntry())
	}

	func getTimeline(in context: Context, completion: @escaping (Timeline<JarvisWidgetEntry>) -> Void) {
		let entry = currentEntry()
		// Refresh at the next known reminder/event time (so the widget flips to "nothing upcoming"
		// promptly), or in an hour as a fallback so a manual snooze/change elsewhere still shows up
		// reasonably soon — this widget has no push mechanism of its own, only what the app last synced.
		let nextRefresh = [entry.reminderAt, entry.eventAt].compactMap { $0 }.filter { $0 > Date() }.min()
			?? Date().addingTimeInterval(3600)
		completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
	}

	private func currentEntry() -> JarvisWidgetEntry {
		let defaults = UserDefaults(suiteName: jarvisAppGroupID)
		let reminderAt = (defaults?.object(forKey: "nextReminderAt") as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }
		let eventAt = (defaults?.object(forKey: "nextEventAt") as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }
		return JarvisWidgetEntry(
			date: Date(),
			reminderText: defaults?.string(forKey: "nextReminderText"),
			reminderAt: reminderAt,
			eventText: defaults?.string(forKey: "nextEventText"),
			eventAt: eventAt
		)
	}
}

struct JarvisWidgetView: View {
	var entry: JarvisWidgetEntry

	var body: some View {
		VStack(alignment: .leading, spacing: 6) {
			Text("JARVIS")
				.font(.system(size: 11, weight: .bold))
				.tracking(1.5)
				.foregroundColor(.secondary)

			if !entry.hasAnything {
				Spacer()
				Text("Nothing upcoming")
					.font(.system(size: 14, weight: .semibold))
				Text("Open Jarvis to add a reminder")
					.font(.system(size: 11))
					.foregroundColor(.secondary)
				Spacer()
			} else {
				Spacer(minLength: 4)
				if let text = entry.reminderText {
					row(icon: "bell.fill", text: text, at: entry.reminderAt)
				}
				if let text = entry.eventText {
					row(icon: "calendar", text: text, at: entry.eventAt)
				}
				Spacer(minLength: 0)
			}
		}
		.padding()
		.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
		.background(Color.black)
	}

	@ViewBuilder
	private func row(icon: String, text: String, at: Date?) -> some View {
		HStack(alignment: .top, spacing: 6) {
			Image(systemName: icon).font(.system(size: 12)).foregroundColor(.white.opacity(0.7))
			VStack(alignment: .leading, spacing: 1) {
				Text(text).font(.system(size: 13, weight: .semibold)).foregroundColor(.white).lineLimit(2)
				if let at {
					Text(at, style: .time).font(.system(size: 11)).foregroundColor(.white.opacity(0.6))
				}
			}
		}
	}
}

struct JarvisWidget: Widget {
	let kind: String = "JarvisWidget"

	var body: some WidgetConfiguration {
		StaticConfiguration(kind: kind, provider: JarvisWidgetProvider()) { entry in
			JarvisWidgetView(entry: entry)
		}
		.configurationDisplayName("Jarvis")
		.description("Your next reminder and calendar event.")
		.supportedFamilies([.systemSmall, .systemMedium])
	}
}
