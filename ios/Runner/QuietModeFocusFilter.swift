import AppIntents
import Foundation

@available(iOS 16.0, *)
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
        _ = QuietModeScheduleriOS.shared.syncFromStoredPlan()
        return .result()
    }
}
