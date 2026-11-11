import WidgetKit

let todayWidgetAppGroupId = "group.com.sabbirba.preconnect.TodayWidgetExtension"
let todayWidgetKind = "TodayWidget"

struct TodayWidgetItem {
  let badge: String
  let title: String
  let subtitle: String
  let trailing: String
  let trailingSub: String
  var startMinutes = -1
  var endMinutes = -1

  var hasTime: Bool { startMinutes >= 0 && startMinutes < endMinutes }
}

struct TodayWidgetEntry: TimelineEntry {
  let date: Date
  let title: String
  let dateText: String
  let items: [TodayWidgetItem]

  func isHighlighted(_ item: TodayWidgetItem) -> Bool {
    guard item.hasTime else { return false }
    let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
    let nowMinutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    let isRunning = { (slot: TodayWidgetItem) in
      slot.hasTime && (slot.startMinutes..<slot.endMinutes).contains(nowMinutes)
    }
    if items.contains(where: isRunning) { return isRunning(item) }
    let nextStart = items.filter { $0.hasTime && $0.startMinutes > nowMinutes }
      .map(\.startMinutes).min()
    return item.startMinutes == nextStart
  }
}

struct TodayWidgetProvider: TimelineProvider {
  func placeholder(in context: Context) -> TodayWidgetEntry {
    TodayWidgetEntry(
      date: Date(),
      title: "Today is Monday",
      dateText: "17 August, 2026",
      items: [
        TodayWidgetItem(
          badge: "05", title: "CSE230",
          subtitle: "11:00 AM - 12:20 PM", trailing: "08H-22C", trailingSub: "TSM"),
        TodayWidgetItem(
          badge: "03", title: "CSE111",
          subtitle: "12:30 PM - 1:50 PM", trailing: "10A-05C", trailingSub: "TAW"),
      ]
    )
  }

  func getSnapshot(in context: Context, completion: @escaping (TodayWidgetEntry) -> Void) {
    completion(readEntry())
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<TodayWidgetEntry>) -> Void)
  {
    let entry = readEntry()
    let now = Date()
    let calendar = Calendar.current
    let startOfDay = calendar.startOfDay(for: now)
    let nextReload = calendar.date(byAdding: .minute, value: 15, to: now) ?? now
    let redrawTimes = Set(entry.items.flatMap { [$0.startMinutes, $0.endMinutes] } + [24 * 60])
      .filter { $0 >= 0 }
      .compactMap { calendar.date(byAdding: .minute, value: $0, to: startOfDay) }
      .filter { $0 > now }
      .sorted()
    let entries = [entry] + redrawTimes.map {
      TodayWidgetEntry(date: $0, title: entry.title, dateText: entry.dateText, items: entry.items)
    }
    completion(Timeline(entries: entries, policy: .after(nextReload)))
  }

  private func readEntry() -> TodayWidgetEntry {
    let preferences = UserDefaults(suiteName: todayWidgetAppGroupId)

    let title = preferences?.string(forKey: "today_title") ?? "Today"
    let dateText = preferences?.string(forKey: "today_date") ?? ""
    let itemCount = preferences?.integer(forKey: "today_item_count") ?? 0

    var items: [TodayWidgetItem] = []
    if itemCount > 0 {
      for slot in 1...itemCount {
        let itemTitle = preferences?.string(forKey: "today_item\(slot)_title") ?? ""
        if itemTitle.isEmpty { continue }
        items.append(
          TodayWidgetItem(
            badge: preferences?.string(forKey: "today_item\(slot)_badge") ?? "",
            title: itemTitle,
            subtitle: preferences?.string(forKey: "today_item\(slot)_subtitle") ?? "",
            trailing: preferences?.string(forKey: "today_item\(slot)_trailing") ?? "",
            trailingSub: preferences?.string(forKey: "today_item\(slot)_trailing_sub") ?? "",
            startMinutes: preferences?.object(forKey: "today_item\(slot)_start") as? Int ?? -1,
            endMinutes: preferences?.object(forKey: "today_item\(slot)_end") as? Int ?? -1
          ))
      }
    }

    return TodayWidgetEntry(date: Date(), title: title, dateText: dateText, items: items)
  }
}
