import AppIntents
import Foundation

@available(macOS 13.0, *)
struct QuietModeFocusFilter: SetFocusFilterIntent {
    static var title: LocalizedStringResource = "Quiet Mode"
    static var description: IntentDescription = IntentDescription("Silences alerts during scheduled classes.")

    @Parameter(title: "Active", default: false)
    var isActive: Bool

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "Quiet Mode",
            subtitle: isActive ? "Active" : "Inactive"
        )
    }

    func perform() async throws -> some IntentResult {
        _ = QuietModeSchedulerMacOS.shared.syncFromStoredPlan()
        return .result()
    }
}
