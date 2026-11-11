import WidgetKit

let todayWidgetAppGroupId = "group.com.sabbirba.preconnect.TodayWidgetExtension"
let todayWidgetKind = "TodayWidget"

struct TodayWidgetItem: Decodable {
  let badge: String
  let title: String
  let subtitle: String
  let trailing: String
  let trailingSub: String
  var startMinutes = -1
  var endMinutes = -1

  var hasTime: Bool { startMinutes >= 0 && startMinutes < endMinutes }

  enum CodingKeys: String, CodingKey {
    case badge, title, subtitle, trailing, trailingSub
    case startMinutes = "start"
    case endMinutes = "end"
  }
}

struct TodayWidgetDay: Decodable {
  let day: Int
  let title: String
  let date: String
  let items: [TodayWidgetItem]
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
    completion(entry(at: Date(), in: readDays()))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<TodayWidgetEntry>) -> Void)
  {
    let now = Date()
    let calendar = Calendar.current
    let days = readDays()
    let redrawTimes = days.flatMap { day -> [Date] in
      guard let start = startOfDay(day.day) else { return [] }
      return ([0] + day.items.flatMap { [$0.startMinutes, $0.endMinutes] })
        .filter { $0 >= 0 }
        .compactMap { calendar.date(byAdding: .minute, value: $0, to: start) }
    }
    .filter { $0 > now }
    let entries = ([now] + Set(redrawTimes).sorted()).map { entry(at: $0, in: days) }
    let nextReload = calendar.date(byAdding: .minute, value: 15, to: now) ?? now
    completion(Timeline(entries: entries, policy: .after(nextReload)))
  }

  private func entry(at date: Date, in days: [TodayWidgetDay]) -> TodayWidgetEntry {
    let day = days.first { $0.day == dayKey(date) }
    return TodayWidgetEntry(
      date: date, title: day?.title ?? "Today", dateText: day?.date ?? "", items: day?.items ?? [])
  }

  private func dayKey(_ date: Date) -> Int {
    let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
    return (parts.year ?? 0) * 10000 + (parts.month ?? 0) * 100 + (parts.day ?? 0)
  }

  private func startOfDay(_ key: Int) -> Date? {
    Calendar.current.date(
      from: DateComponents(year: key / 10000, month: key / 100 % 100, day: key % 100))
  }

  private func readDays() -> [TodayWidgetDay] {
    guard
      let raw = UserDefaults(suiteName: todayWidgetAppGroupId)?.string(forKey: "today_days"),
      let data = raw.data(using: .utf8)
    else { return [] }
    return (try? JSONDecoder().decode([TodayWidgetDay].self, from: data)) ?? []
  }
}
