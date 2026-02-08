import AlarmKit
import AppIntents

@available(iOS 26.0, *)
public struct PauseIntent: LiveActivityIntent {
    public func perform() throws -> some IntentResult {
        try AlarmManager.shared.pause(id: UUID(uuidString: alarmID)!)
        return .result()
    }
    
    public static var title: LocalizedStringResource = "Pause"
    public static var description = IntentDescription("Pause a countdown")
    
    @Parameter(title: "alarmID")
    public var alarmID: String
    
    public init(alarmID: String) {
        self.alarmID = alarmID
    }
    
    public init() {
        self.alarmID = ""
    }
}

@available(iOS 26.0, *)
public struct StopIntent: LiveActivityIntent {
    public func perform() throws -> some IntentResult {
        try AlarmManager.shared.stop(id: UUID(uuidString: alarmID)!)
        return .result()
    }
    
    public static var title: LocalizedStringResource = "Stop"
    public static var description = IntentDescription("Stop an alert")
    
    @Parameter(title: "alarmID")
    public var alarmID: String
    
    public init(alarmID: String) {
        self.alarmID = alarmID
    }
    
    public init() {
        self.alarmID = ""
    }
}

@available(iOS 26.0, *)
public struct RepeatIntent: LiveActivityIntent {
    public func perform() throws -> some IntentResult {
        try AlarmManager.shared.countdown(id: UUID(uuidString: alarmID)!)
        return .result()
    }
    
    public static var title: LocalizedStringResource = "Repeat"
    public static var description = IntentDescription("Repeat a countdown")
    
    @Parameter(title: "alarmID")
    public var alarmID: String
    
    public init(alarmID: String) {
        self.alarmID = alarmID
    }
    
    public init() {
        self.alarmID = ""
    }
}

@available(iOS 26.0, *)
public struct ResumeIntent: LiveActivityIntent {
    public func perform() throws -> some IntentResult {
        try AlarmManager.shared.resume(id: UUID(uuidString: alarmID)!)
        return .result()
    }
    
    public static var title: LocalizedStringResource = "Resume"
    public static var description = IntentDescription("Resume a countdown")
    
    @Parameter(title: "alarmID")
    public var alarmID: String
    
    public init(alarmID: String) {
        self.alarmID = alarmID
    }
    
    public init() {
        self.alarmID = ""
    }
}

@available(iOS 26.0, *)
public struct OpenAlarmAppIntent: LiveActivityIntent {
    public func perform() throws -> some IntentResult {
        try AlarmManager.shared.stop(id: UUID(uuidString: alarmID)!)
        return .result()
    }
    
    public static var title: LocalizedStringResource = "Open App"
    public static var description = IntentDescription("Opens the Sample app")
    public static var openAppWhenRun = true
    
    @Parameter(title: "alarmID")
    public var alarmID: String
    
    public init(alarmID: String) {
        self.alarmID = alarmID
    }
    
    public init() {
        self.alarmID = ""
    }
}
