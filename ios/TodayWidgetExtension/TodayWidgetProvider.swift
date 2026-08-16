import WidgetKit

let todayWidgetAppGroupId = "group.com.sabbirba.preconnect.TodayWidgetExtension"
let todayWidgetKind = "TodayWidget"

struct TodayWidgetItem {
  let badge: String
  let badgeColor: String
  let title: String
  let subtitle: String
  let trailing: String
  let trailingSub: String
}

struct TodayWidgetEntry: TimelineEntry {
  let date: Date
  let title: String
  let dateText: String
  let items: [TodayWidgetItem]
}

struct TodayWidgetProvider: TimelineProvider {
  func placeholder(in context: Context) -> TodayWidgetEntry {
    TodayWidgetEntry(
      date: Date(),
      title: "Today is Monday",
      dateText: "17 August, 2026",
      items: [
        TodayWidgetItem(
          badge: "05", badgeColor: "#FF1E6BE3", title: "CSE230",
          subtitle: "11:00 AM - 12:20 PM", trailing: "08H-22C", trailingSub: "TSM"),
        TodayWidgetItem(
          badge: "03", badgeColor: "#FF1E6BE3", title: "CSE111",
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
    let nextRefresh = Calendar.current.date(byAdding: .minute, value: 5, to: Date()) ?? Date()
      .addingTimeInterval(300)
    completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
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
            badgeColor: preferences?.string(forKey: "today_item\(slot)_badge_color") ?? "#FF1E6BE3",
            title: itemTitle,
            subtitle: preferences?.string(forKey: "today_item\(slot)_subtitle") ?? "",
            trailing: preferences?.string(forKey: "today_item\(slot)_trailing") ?? "",
            trailingSub: preferences?.string(forKey: "today_item\(slot)_trailing_sub") ?? ""
          ))
      }
    }

    return TodayWidgetEntry(date: Date(), title: title, dateText: dateText, items: items)
  }
}
