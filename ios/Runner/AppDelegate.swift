import EventKit
import Flutter
import StoreKit
import UIKit

let preconnectPendingShortcutActionKey = "flutter.pending_shortcut_action"

@main
@objc
class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate,
  UIDocumentInteractionControllerDelegate
{
  private var documentController: UIDocumentInteractionController?

  private func cacheShortcutAction(_ type: String) {
    UserDefaults.standard.set(type, forKey: preconnectPendingShortcutActionKey)
  }

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    purgeLargeUserDefaultsEntries()
    if let shortcutItem = launchOptions?[.shortcutItem] as? UIApplicationShortcutItem {
      cacheShortcutAction(shortcutItem.type)
    }
    if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
      let controller = scene.windows.first?.rootViewController as? FlutterViewController
    {
      registerQuietModeChannel(binaryMessenger: controller.binaryMessenger)
      registerNativePrintChannel(binaryMessenger: controller.binaryMessenger)
      registerBackgroundPermissionChannel(binaryMessenger: controller.binaryMessenger)
      registerStoreChannel(binaryMessenger: controller.binaryMessenger)
      registerFileChannel(binaryMessenger: controller.binaryMessenger)
      registerCalendarChannel(binaryMessenger: controller.binaryMessenger)
      IosNetworkAssist.register(binaryMessenger: controller.binaryMessenger)
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func applicationWillEnterForeground(_ application: UIApplication) {
    super.applicationWillEnterForeground(application)
    _ = QuietModeScheduleriOS.shared.syncFromStoredPlan()
  }

  override func application(
    _ application: UIApplication,
    performActionFor shortcutItem: UIApplicationShortcutItem,
    completionHandler: @escaping (Bool) -> Void
  ) {
    cacheShortcutAction(shortcutItem.type)
    completionHandler(true)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "PreConnectQuietMode") {
      registerQuietModeChannel(binaryMessenger: registrar.messenger())
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "PreConnectNativePrint") {
      registerNativePrintChannel(binaryMessenger: registrar.messenger())
    }
    if let registrar = engineBridge.pluginRegistry.registrar(
      forPlugin: "PreConnectBackgroundPermission")
    {
      registerBackgroundPermissionChannel(binaryMessenger: registrar.messenger())
    }
    if let registrar = engineBridge.pluginRegistry.registrar(
      forPlugin: "PreConnectIosNetworkAssist")
    {
      IosNetworkAssist.register(binaryMessenger: registrar.messenger())
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "PreConnectStore") {
      registerStoreChannel(binaryMessenger: registrar.messenger())
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "PreConnectFile") {
      registerFileChannel(binaryMessenger: registrar.messenger())
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "PreConnectCalendar") {
      registerCalendarChannel(binaryMessenger: registrar.messenger())
    }

    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  private func registerFileChannel(binaryMessenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "preconnect/file",
      binaryMessenger: binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "open" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let self,
        let arguments = call.arguments as? [String: Any],
        let path = arguments["path"] as? String,
        FileManager.default.fileExists(atPath: path)
      else {
        result(false)
        return
      }
      let controller = UIDocumentInteractionController(
        url: URL(fileURLWithPath: path)
      )
      controller.delegate = self
      self.documentController = controller
      result(controller.presentPreview(animated: true))
    }
  }

  func documentInteractionControllerViewControllerForPreview(
    _ controller: UIDocumentInteractionController
  ) -> UIViewController {
    return UIApplication.preconnectTopViewController() ?? window?.rootViewController ?? UIViewController()
  }

  private func registerCalendarChannel(binaryMessenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "preconnect/calendar",
      binaryMessenger: binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "add" else {
        result(FlutterMethodNotImplemented)
        return
      }
      self?.saveReminder(call: call, result: result)
    }
  }

  private func saveReminder(
    call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
    guard let arguments = call.arguments as? [String: Any],
      let title = arguments["title"] as? String,
      let start = arguments["start"] as? NSNumber
    else {
      result(false)
      return
    }
    let store = EKEventStore()
    let saveReminderBlock = {
      let reminderCalendar = store.defaultCalendarForNewReminders()
        ?? store.calendars(for: .reminder).first(where: { $0.allowsContentModifications })
      guard let calendar = reminderCalendar else {
        result(false)
        return
      }
      let reminder = EKReminder(eventStore: store)
      reminder.title = title
      if let notes = arguments["description"] as? String, !notes.isEmpty {
        reminder.notes = notes
      }
      if let location = arguments["location"] as? String, !location.isEmpty {
        reminder.location = location
      }
      reminder.calendar = calendar
      let alarmDate = Date(timeIntervalSince1970: start.doubleValue / 1000)
      reminder.dueDateComponents = Calendar.current.dateComponents(
        [.year, .month, .day, .hour, .minute],
        from: alarmDate
      )
      reminder.addAlarm(EKAlarm(absoluteDate: alarmDate))

      if let frequencyValue = arguments["frequency"] as? NSNumber,
        let frequency = EKRecurrenceFrequency(rawValue: frequencyValue.intValue)
      {
        let interval = (arguments["interval"] as? NSNumber)?.intValue ?? 1
        reminder.recurrenceRules = [
          EKRecurrenceRule(
            recurrenceWith: frequency,
            interval: interval,
            end: nil
          )
        ]
      }

      do {
        try store.save(reminder, commit: true)
        result(true)
      } catch {
        result(false)
      }
    }

    if #available(iOS 17.0, *) {
      let status = EKEventStore.authorizationStatus(for: .reminder)
      if status == .fullAccess || status == .authorized {
        saveReminderBlock()
      } else {
        store.requestFullAccessToReminders { granted, _ in
          DispatchQueue.main.async {
            if granted {
              saveReminderBlock()
            } else {
              result(false)
            }
          }
        }
      }
    } else {
      switch EKEventStore.authorizationStatus(for: .reminder) {
      case .authorized:
        saveReminderBlock()
      case .notDetermined:
        store.requestAccess(to: .reminder) { granted, _ in
          DispatchQueue.main.async {
            if granted {
              saveReminderBlock()
            } else {
              result(false)
            }
          }
        }
      default:
        result(false)
      }
    }
  }

  private func registerStoreChannel(binaryMessenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "preconnect/store",
      binaryMessenger: binaryMessenger
    )
    channel.setMethodCallHandler { call, result in
      guard
        let scene = UIApplication.shared.connectedScenes
          .compactMap({ $0 as? UIWindowScene })
          .first(where: { $0.activationState == .foregroundActive })
      else {
        result(
          FlutterError(
            code: "REVIEW_UNAVAILABLE",
            message: "No active window scene",
            details: nil
          )
        )
        return
      }
      switch call.method {
      case "isReviewAvailable":
        result(true)
      case "requestReview":
        if #available(iOS 18.0, *) {
          Task { @MainActor in
            await AppStore.requestReview(in: scene)
            result(nil)
          }
        } else {
          SKStoreReviewController.requestReview(in: scene)
          result(nil)
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func registerQuietModeChannel(binaryMessenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "preconnect/quiet_mode",
      binaryMessenger: binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(
          FlutterError(
            code: "QUIET_MODE_CONTEXT",
            message: "App context unavailable",
            details: nil
          )
        )
        return
      }
      switch call.method {
      case "setQuietMode":
        self.setQuietMode(call: call, result: result)
      case "openQuietModeSettings":
        self.openQuietModeSettings(result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func setQuietMode(call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    let enabled = args["enabled"] as? Bool ?? false
    let rawWindows = args["windows"] as? [[String: Any]] ?? []

    QuietModeScheduleriOS.shared.handleSetQuietMode(
      enabled: enabled,
      windows: rawWindows
    ) { response in
      result(response)
    }
  }

  private func openQuietModeSettings(result: @escaping FlutterResult) {
    DispatchQueue.main.async {
      var candidateURLs: [URL] = []

      if #available(iOS 15.0, *) {
        if let focusURL = URL(string: "App-Prefs:DO_NOT_DISTURB") {
          candidateURLs.append(focusURL)
        }
      }
      if #available(iOS 16.0, *) {
        if let notifURL = URL(string: UIApplication.openNotificationSettingsURLString) {
          candidateURLs.append(notifURL)
        }
      }
      if let appSettingsURL = URL(string: UIApplication.openSettingsURLString) {
        candidateURLs.append(appSettingsURL)
      }

      guard let targetURL = candidateURLs.first(where: { UIApplication.shared.canOpenURL($0) })
      else {
        result(
          FlutterError(
            code: "QUIET_MODE_UNAVAILABLE",
            message: "Unable to open settings",
            details: nil
          ))
        return
      }

      UIApplication.shared.open(targetURL, options: [:]) { success in
        result([
          "status": "opened_settings",
          "applied": false,
          "enabled": true,
          "message": success
            ? "Opened Focus/Notification settings. Enable scheduled Focus or allow PreConnect notifications."
            : "Could not open settings.",
        ])
      }
    }
  }

  private func registerNativePrintChannel(binaryMessenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "preconnect/native_print",
      binaryMessenger: binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(
          FlutterError(
            code: "NATIVE_PRINT_CONTEXT",
            message: "App context unavailable",
            details: nil
          )
        )
        return
      }
      switch call.method {
      case "printPdf":
        self.printPdf(call: call, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func printPdf(call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    let rawPath =
      (args["filePath"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let rawJobName =
      (args["jobName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let jobName = rawJobName.isEmpty ? "PreConnect PDF" : rawJobName
    guard !rawPath.isEmpty else {
      result(
        FlutterError(
          code: "INVALID_PATH",
          message: "Missing file path",
          details: nil
        )
      )
      return
    }

    let fileURL = URL(fileURLWithPath: rawPath)
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      result(
        FlutterError(
          code: "FILE_NOT_FOUND",
          message: "Selected PDF file was not found",
          details: nil
        )
      )
      return
    }
    guard UIPrintInteractionController.isPrintingAvailable else {
      result(
        FlutterError(
          code: "PRINT_UNAVAILABLE",
          message: "Print service unavailable",
          details: nil
        )
      )
      return
    }

    DispatchQueue.main.async {
      let controller = UIPrintInteractionController.shared
      let printInfo = UIPrintInfo.printInfo()
      printInfo.jobName = jobName
      printInfo.outputType = .general
      controller.printInfo = printInfo
      controller.printingItem = fileURL
      controller.showsNumberOfCopies = true

      controller.present(animated: true) { _, completed, error in
        if let error {
          result(
            FlutterError(
              code: "PRINT_ERROR",
              message: error.localizedDescription,
              details: nil
            )
          )
          return
        }
        result(completed)
      }
    }
  }

  private func registerBackgroundPermissionChannel(binaryMessenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "preconnect/background_permission",
      binaryMessenger: binaryMessenger
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "getBackgroundRefreshStatus":
        let status = UIApplication.shared.backgroundRefreshStatus
        switch status {
        case .available:
          result("allowed")
        case .denied:
          result("denied")
        case .restricted:
          result("restricted")
        @unknown default:
          result("unknown")
        }
      case "openBackgroundSettings":
        DispatchQueue.main.async {
          if let url = URL(string: UIApplication.openSettingsURLString) {
            if UIApplication.shared.canOpenURL(url) {
              UIApplication.shared.open(url, options: [:]) { success in
                result(success)
              }
              return
            }
          }
          result(false)
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}

private func resolvedEnvValue(forKey key: String) -> String? {
  let plistValue = (Bundle.main.object(forInfoDictionaryKey: key) as? String)?
    .trimmingCharacters(in: .whitespacesAndNewlines)
  if let plistValue,
    !plistValue.isEmpty,
    !(plistValue.hasPrefix("$(") && plistValue.hasSuffix(")"))
  {
    return plistValue
  }

  let envValue = ProcessInfo.processInfo.environment[key]?
    .trimmingCharacters(in: .whitespacesAndNewlines)
  if let envValue,
    !envValue.isEmpty,
    !(envValue.hasPrefix("$(") && envValue.hasSuffix(")"))
  {
    return envValue
  }
  return nil
}

extension UIApplication {
  fileprivate static func preconnectTopViewController(
    base: UIViewController? = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
      .first(where: \.isKeyWindow)?
      .rootViewController
  ) -> UIViewController? {
    if let navigation = base as? UINavigationController {
      return preconnectTopViewController(base: navigation.visibleViewController)
    }
    if let tab = base as? UITabBarController, let selected = tab.selectedViewController {
      return preconnectTopViewController(base: selected)
    }
    if let presented = base?.presentedViewController {
      return preconnectTopViewController(base: presented)
    }
    return base
  }
}

private func purgeLargeUserDefaultsEntries() {
  let defaults = UserDefaults.standard
  let maxBytes = 256 * 1024
  let whitelist: Set<String> = [
    "preconnect.quiet_mode_plan_v1",
    preconnectPendingShortcutActionKey,
  ]
  var removed = false
  for key in defaults.dictionaryRepresentation().keys {
    if whitelist.contains(key) { continue }
    if let str = defaults.string(forKey: key) {
      if str.utf8.count > maxBytes {
        defaults.removeObject(forKey: key)
        removed = true
      }
    } else if let data = defaults.data(forKey: key) {
      if data.count > maxBytes {
        defaults.removeObject(forKey: key)
        removed = true
      }
    }
  }
  if removed {
    defaults.synchronize()
  }
}
