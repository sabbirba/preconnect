import AppIntents
import Foundation

@available(macOS 13.0, *)
struct QuietModeFocusFilter: SetFocusFilterIntent {
    static var title: LocalizedStringResource = "Quiet Mode"
    static var description: IntentDescription = IntentDescription("Silences alerts during scheduled classes.")

    @Parameter(title: "Active", default: false)
    var isActive: Bool

    func perform() async throws -> some IntentResult {
        _ = QuietModeSchedulerMacOS.shared.syncFromStoredPlan()
        return .result()
    }
}
