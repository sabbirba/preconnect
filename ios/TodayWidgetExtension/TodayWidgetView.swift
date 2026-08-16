import SwiftUI
import WidgetKit

extension Color {
  init(hex: String) {
    var hexValue = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    hexValue = hexValue.hasPrefix("#") ? String(hexValue.dropFirst()) : hexValue
    var rgba: UInt64 = 0
    Scanner(string: hexValue).scanHexInt64(&rgba)
    let a = Double((rgba & 0xFF00_0000) >> 24) / 255
    let r = Double((rgba & 0x00FF_0000) >> 16) / 255
    let g = Double((rgba & 0x0000_FF00) >> 8) / 255
    let b = Double(rgba & 0x0000_00FF) / 255
    self.init(.sRGB, red: r, green: g, blue: b, opacity: a == 0 ? 1 : a)
  }
}

private let todayCardBackground = Color.white
private let todayTextPrimary = Color.black.opacity(0.87)
private let todayTextSecondary = Color.black.opacity(0.54)

struct TodayWidgetCard: View {
  let item: TodayWidgetItem

  var body: some View {
    HStack(alignment: .center, spacing: 12) {
      Text(item.badge)
        .font(.system(size: 16, weight: .bold))
        .foregroundStyle(Color(hex: item.badgeColor))
        .frame(width: 40)

      VStack(alignment: .leading, spacing: 2) {
        Text(item.title)
          .font(.system(size: 14, weight: .bold))
          .foregroundStyle(todayTextPrimary)
          .lineLimit(2)
        Text(item.subtitle)
          .font(.system(size: 11))
          .foregroundStyle(todayTextSecondary)
          .lineLimit(2)
      }

      Spacer(minLength: 8)

      if !item.trailing.isEmpty {
        VStack(alignment: .trailing, spacing: 2) {
          Text(item.trailing)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(todayTextPrimary)
            .lineLimit(1)
          if !item.trailingSub.isEmpty {
            Text(item.trailingSub)
              .font(.system(size: 11))
              .foregroundStyle(todayTextSecondary)
              .lineLimit(1)
          }
        }
      }
    }
    .padding(14)
    .background(todayCardBackground)
    .clipShape(RoundedRectangle(cornerRadius: 18))
  }
}

struct TodayWidgetEntryView: View {
  var entry: TodayWidgetProvider.Entry

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(alignment: .center) {
        Text(entry.title)
          .font(.system(size: 16, weight: .bold))
          .foregroundStyle(todayTextPrimary)
          .lineLimit(1)

        Spacer()

        Text(entry.dateText)
          .font(.system(size: 16, weight: .bold))
          .foregroundStyle(todayTextPrimary)
          .lineLimit(1)

        Button(intent: SyncTodayWidgetIntent()) {
          if entry.isSyncing {
            ProgressView()
              .progressViewStyle(.circular)
              .tint(Color(hex: "#FF1E6BE3"))
              .scaleEffect(0.7)
              .frame(width: 16, height: 16)
          } else {
            Image(systemName: "arrow.triangle.2.circlepath")
              .font(.system(size: 14, weight: .bold))
              .foregroundStyle(Color(hex: "#FF1E6BE3"))
              .frame(width: 16, height: 16)
          }
        }
        .buttonStyle(.plain)
        .padding(.leading, 8)
      }
      .padding(10)
      .background(todayCardBackground)
      .clipShape(RoundedRectangle(cornerRadius: 18))

      ForEach(Array(entry.items.enumerated()), id: \.offset) { _, item in
        TodayWidgetCard(item: item)
      }

      if entry.items.isEmpty {
        TodayWidgetCard(
          item: TodayWidgetItem(
            badge: "--", badgeColor: "#FF1E6BE3", title: "No Classes Today",
            subtitle: "Enjoy your day off.", trailing: "", trailingSub: ""))
      }

      Spacer(minLength: 0)
    }
    .padding(14)
    .unredacted()
    .containerBackground(.clear, for: .widget)
  }
}

struct TodayWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: todayWidgetKind, provider: TodayWidgetProvider()) { entry in
      TodayWidgetEntryView(entry: entry)
    }
    .configurationDisplayName("Today's Schedule")
    .description("Shows today's classes, exams, and status.")
    .supportedFamilies([.systemMedium, .systemLarge])
    .contentMarginsDisabled()
  }
}
