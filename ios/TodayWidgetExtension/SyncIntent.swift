import AppIntents
import home_widget

@available(iOS 17.0, *)
struct SyncTodayWidgetIntent: AppIntent {
  static var title: LocalizedStringResource = "Sync Today's Schedule"

  private static let appGroupId = "group.com.sabbirba.preconnect.TodayWidgetExtension"

  init() {}

  func perform() async throws -> some IntentResult {
    await HomeWidgetBackgroundWorker.run(
      url: URL(string: "todaywidget://sync"), appGroup: Self.appGroupId)
    return .result()
  }
}

@available(iOS 17.0, *)
@available(iOSApplicationExtension, unavailable)
extension SyncTodayWidgetIntent: ForegroundContinuableIntent {}
