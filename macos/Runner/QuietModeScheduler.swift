import Foundation

private let kQuietModePlanKey = "preconnect.quiet_mode_plan_v1"

struct QuietModeWindowMacOS {
    let startAtMs: Int64
    let endAtMs: Int64
    let source: String
    let label: String

    var startDate: Date { Date(timeIntervalSince1970: Double(startAtMs) / 1000.0) }
    var endDate: Date { Date(timeIntervalSince1970: Double(endAtMs) / 1000.0) }

    func toDict() -> [String: Any] {
        return ["startAt": startAtMs, "endAt": endAtMs, "source": source, "label": label]
    }

    static func from(_ dict: [String: Any]) -> QuietModeWindowMacOS? {
        let start = dict["startAt"] as? Int64 ?? Int64(dict["startAt"] as? Double ?? 0)
        let end = dict["endAt"] as? Int64 ?? Int64(dict["endAt"] as? Double ?? 0)
        guard start > 0, end > start else { return nil }
        return QuietModeWindowMacOS(
            startAtMs: start,
            endAtMs: end,
            source: dict["source"] as? String ?? "",
            label: dict["label"] as? String ?? ""
        )
    }
}

final class QuietModeSchedulerMacOS {
    static let shared = QuietModeSchedulerMacOS()
    private init() {}

    func handleSetQuietMode(
        enabled: Bool,
        windows rawWindows: [[String: Any]],
        completion: @escaping ([String: Any]) -> Void
    ) {
        guard enabled else {
            savePlan([])
            completion(["status": "disabled", "applied": true, "enabled": false, "message": "Quiet Mode off."])
            return
        }

        let now = Date()
        let parsed = rawWindows.compactMap { QuietModeWindowMacOS.from($0) }
            .filter { $0.endDate > now }

        savePlan(parsed)

        let activeNow = isActiveNow(parsed)
        completion([
            "status": activeNow ? "enabled" : "scheduled",
            "applied": true,
            "enabled": activeNow,
            "message": activeNow ? "Class in progress." : "Quiet Mode scheduled.",
        ])
    }

    func syncFromStoredPlan() -> [String: Any] {
        let now = Date()
        let windows = loadPlan().filter { $0.endDate > now }
        if windows.isEmpty {
            if loadPlan().isEmpty == false { savePlan([]) }
            return ["status": "disabled", "applied": true, "enabled": false, "message": "Quiet Mode off."]
        }
        let activeNow = isActiveNow(windows)
        return [
            "status": activeNow ? "enabled" : "scheduled",
            "applied": true,
            "enabled": activeNow,
            "message": activeNow ? "Class in progress." : "Quiet Mode synced.",
        ]
    }

    private func isActiveNow(_ windows: [QuietModeWindowMacOS]) -> Bool {
        let now = Date()
        return windows.contains { $0.startDate <= now && now < $0.endDate }
    }

    private func savePlan(_ windows: [QuietModeWindowMacOS]) {
        let dicts = windows.map { $0.toDict() }
        if let data = try? JSONSerialization.data(withJSONObject: dicts) {
            UserDefaults.standard.set(data, forKey: kQuietModePlanKey)
        } else {
            UserDefaults.standard.removeObject(forKey: kQuietModePlanKey)
        }
    }

    private func loadPlan() -> [QuietModeWindowMacOS] {
        guard let data = UserDefaults.standard.data(forKey: kQuietModePlanKey),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return [] }
        return raw.compactMap { QuietModeWindowMacOS.from($0) }
    }
}
