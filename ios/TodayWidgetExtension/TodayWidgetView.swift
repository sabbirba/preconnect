import SwiftUI
import WidgetKit

private let todayCardBackground = Color.white.opacity(0.15)
private let todayCardBorder = Color.white.opacity(0.20)
private let todayTextPrimary = Color.white

struct TodayWidgetCard: View {
  let item: TodayWidgetItem

  var body: some View {
    HStack(alignment: .center, spacing: 12) {
      Text(item.badge)
        .font(.system(size: 16, weight: .bold))
        .foregroundStyle(todayTextPrimary)
        .frame(width: 40)

      VStack(alignment: .leading, spacing: 2) {
        Text(item.title)
          .font(.system(size: 14, weight: .bold))
          .foregroundStyle(todayTextPrimary)
          .lineLimit(2)
        Text(item.subtitle)
          .font(.system(size: 11))
          .foregroundStyle(todayTextPrimary)
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
              .foregroundStyle(todayTextPrimary)
              .lineLimit(1)
          }
        }
      }
    }
    .padding(14)
    .background(todayCardBackground, in: RoundedRectangle(cornerRadius: 18))
    .overlay {
      RoundedRectangle(cornerRadius: 18)
        .stroke(todayCardBorder, lineWidth: 1)
    }
  }
}

struct TodayWidgetEntryView: View {
  @Environment(\.widgetFamily) private var family
  var entry: TodayWidgetProvider.Entry

  private var visibleItems: [TodayWidgetItem] {
    family == .systemMedium ? Array(entry.items.prefix(1)) : entry.items
  }

  private var emptyItem: TodayWidgetItem {
    TodayWidgetItem(
      badge: "--", title: "No Classes Today",
      subtitle: "Enjoy your day off.", trailing: "", trailingSub: "")
  }

  private let openAppURL = URL(string: "preconnect://today")!

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Link(destination: openAppURL) {
        HStack(alignment: .center, spacing: 8) {
          Text(entry.title)
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(todayTextPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(maxWidth: .infinity, alignment: .leading)

          Text(entry.dateText)
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(todayTextPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)

      ForEach(Array(visibleItems.enumerated()), id: \.offset) { _, item in
        Link(destination: openAppURL) {
          TodayWidgetCard(item: item)
        }
        .buttonStyle(.plain)
      }

      if visibleItems.isEmpty {
        Link(destination: openAppURL) {
          TodayWidgetCard(item: emptyItem)
        }
        .buttonStyle(.plain)
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
