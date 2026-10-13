import SwiftUI
import WidgetKit

struct TodayWidgetCard: View {
  let item: TodayWidgetItem

  var body: some View {
    HStack(alignment: .center, spacing: 12) {
      Text(item.badge)
        .font(.system(size: 16, weight: .bold))
        .foregroundStyle(Color.primary)
        .frame(width: 36)

      VStack(alignment: .leading, spacing: 2) {
        Text(item.title)
          .font(.system(size: 14, weight: .bold))
          .foregroundStyle(Color.primary)
          .lineLimit(2)
        Text(item.subtitle)
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(Color.secondary)
          .lineLimit(2)
      }

      Spacer(minLength: 8)

      if !item.trailing.isEmpty {
        VStack(alignment: .trailing, spacing: 2) {
          Text(item.trailing)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(Color.primary)
            .lineLimit(1)
          if !item.trailingSub.isEmpty {
            Text(item.trailingSub)
              .font(.system(size: 11, weight: .medium))
              .foregroundStyle(Color.secondary)
              .lineLimit(1)
          }
        }
      }
    }
    .padding(12)
    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    .overlay {
      RoundedRectangle(cornerRadius: 16)
        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
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

  @ViewBuilder
  var body: some View {
    switch family {
    case .accessoryInline:
      if let first = entry.items.first {
        Text("\(first.title) • \(first.trailing.isEmpty ? first.subtitle : first.trailing)")
      } else {
        Text("No Classes Today")
      }
    case .accessoryRectangular:
      if let first = entry.items.first {
        VStack(alignment: .leading, spacing: 2) {
          HStack(spacing: 4) {
            Text(first.title)
              .font(.headline)
            if !first.badge.isEmpty {
              Text("Sec \(first.badge)")
                .font(.caption2)
            }
            Spacer()
            if !first.trailing.isEmpty {
              Text(first.trailing)
                .font(.caption2)
            }
          }
          Text(first.subtitle)
            .font(.caption)
            .lineLimit(1)
          if !first.trailingSub.isEmpty {
            Text(first.trailingSub)
              .font(.caption2)
              .foregroundStyle(.secondary)
          }
        }
        .containerBackground(for: .widget) {
          Color.clear
        }
      } else {
        VStack(alignment: .leading, spacing: 2) {
          Text("No Classes Today")
            .font(.headline)
          Text("Enjoy your day off.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .containerBackground(for: .widget) {
          Color.clear
        }
      }
    default:
      VStack(alignment: .leading, spacing: 6) {
        Link(destination: openAppURL) {
          HStack(alignment: .center, spacing: 8) {
            Text(entry.title)
              .font(.system(size: 15, weight: .bold))
              .foregroundStyle(Color.primary)
              .lineLimit(1)
              .minimumScaleFactor(0.75)
              .frame(maxWidth: .infinity, alignment: .leading)

            Text(entry.dateText)
              .font(.system(size: 14, weight: .semibold))
              .foregroundStyle(Color.secondary)
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
      .containerBackground(Color(uiColor: .systemGroupedBackground), for: .widget)
    }
  }
}

struct TodayWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: todayWidgetKind, provider: TodayWidgetProvider()) { entry in
      TodayWidgetEntryView(entry: entry)
    }
    .configurationDisplayName("Today's Schedule")
    .description("Shows today's classes, exams, and status.")
    .supportedFamilies([.systemMedium, .systemLarge, .accessoryRectangular, .accessoryInline])
    .contentMarginsDisabled()
  }
}
