
import WidgetKit
import SwiftUI

private enum AppGroupStore {
    static let suiteName = "group.com.sabbirba.preconnect"
    static let pendingShortcutKey = "flutter.pending_shortcut_action"
    static let alarmSnapshotKey = "widget_alarm_snapshot"
    static let alarmSnapshotFireDateKey = "widget_alarm_snapshot_fire_date"

    static var pendingShortcutAction: String? {
        UserDefaults(suiteName: suiteName)?.string(forKey: pendingShortcutKey)
    }

    static var alarmSnapshot: (label: String, fireDate: Date)? {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return nil }
        let label = defaults.string(forKey: alarmSnapshotKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let fireDateMillis = defaults.object(forKey: alarmSnapshotFireDateKey) as? Int64
        guard !label.isEmpty, let fireDateMillis else { return nil }
        return (label, Date(timeIntervalSince1970: TimeInterval(fireDateMillis) / 1000.0))
    }
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), emoji: "😀", shortcutAction: nil, alarmSnapshot: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> ()) {
        let entry = SimpleEntry(
            date: Date(),
            emoji: "😀",
            shortcutAction: AppGroupStore.pendingShortcutAction,
            alarmSnapshot: AppGroupStore.alarmSnapshot
        )
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        var entries: [SimpleEntry] = []

        let currentDate = Date()
        for hourOffset in 0 ..< 5 {
            let entryDate = Calendar.current.date(byAdding: .hour, value: hourOffset, to: currentDate)!
            let entry = SimpleEntry(
                date: entryDate,
                emoji: "😀",
                shortcutAction: AppGroupStore.pendingShortcutAction,
                alarmSnapshot: AppGroupStore.alarmSnapshot
            )
            entries.append(entry)
        }

        let timeline = Timeline(entries: entries, policy: .atEnd)
        completion(timeline)
    }

}

struct SimpleEntry: TimelineEntry {
    let date: Date
    let emoji: String
    let shortcutAction: String?
    let alarmSnapshot: (label: String, fireDate: Date)?
}

struct AlarmkitWidgetEntryView : View {
    var entry: Provider.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Time:")
            Text(entry.date, style: .time)

            Text("Emoji:")
            Text(entry.emoji)

            Text("Last app action:")
            Text(entry.shortcutAction ?? "None")

            Text("Next alarm:")
            if let alarm = entry.alarmSnapshot {
                Text(alarm.label)
                Text(alarm.fireDate, style: .time)
            } else {
                Text("None")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AlarmkitWidget: Widget {
    let kind: String = "AlarmkitWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            if #available(iOS 17.0, *) {
                AlarmkitWidgetEntryView(entry: entry)
                    .containerBackground(.fill.tertiary, for: .widget)
            } else {
                AlarmkitWidgetEntryView(entry: entry)
                    .padding()
                    .background()
            }
        }
        .configurationDisplayName("My Widget")
        .description("This is an example widget.")
    }
}
#Preview(as: .systemSmall) {
    AlarmkitWidget()
} timeline: {
    SimpleEntry(
        date: .now,
        emoji: "😀",
        shortcutAction: "quick.profile",
        alarmSnapshot: (label: "MATH101 Class Reminder", fireDate: .now.addingTimeInterval(3600))
    )
    SimpleEntry(date: .now, emoji: "🤩", shortcutAction: nil, alarmSnapshot: nil)
}
