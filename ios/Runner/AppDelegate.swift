import Flutter
import UIKit

let preconnectPendingShortcutActionKey = "flutter.pending_shortcut_action"

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private func cacheShortcutAction(_ type: String) {
    UserDefaults.standard.set(type, forKey: preconnectPendingShortcutActionKey)
  }

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if let shortcutItem = launchOptions?[.shortcutItem] as? UIApplicationShortcutItem {
      cacheShortcutAction(shortcutItem.type)
    }
    if let controller = window?.rootViewController as? FlutterViewController {
      registerQuietModeChannel(binaryMessenger: controller.binaryMessenger)
      registerNativePrintChannel(binaryMessenger: controller.binaryMessenger)
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
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

    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
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
    let source = (args["source"] as? String ?? "sync").trimmingCharacters(in: .whitespacesAndNewlines)
    if !enabled {
      result([
        "status": "disabled",
        "applied": true,
        "enabled": false,
        "message": "Quiet Mode disabled.",
      ])
      return
    }

    if source != "user" {
      result([
        "status": "scheduled",
        "applied": false,
        "enabled": true,
        "message": "Quiet Mode saved for iPhone.",
      ])
      return
    }

    openQuietModeSettings(result: result)
  }

  private func openQuietModeSettings(result: @escaping FlutterResult) {
    DispatchQueue.main.async {
      var candidateURLs: [URL] = []
      if #available(iOS 16.0, *) {
        if let notificationSettingsURL = URL(
          string: UIApplication.openNotificationSettingsURLString
        ) {
          candidateURLs.append(notificationSettingsURL)
        }
      }
      if let appSettingsURL = URL(string: UIApplication.openSettingsURLString) {
        candidateURLs.append(appSettingsURL)
      }

      guard let targetURL = candidateURLs.first(where: { UIApplication.shared.canOpenURL($0) }) else {
        result(
          FlutterError(
            code: "QUIET_MODE_UNAVAILABLE",
            message: "Unable to open notification settings",
            details: nil
          )
        )
        return
      }

      UIApplication.shared.open(targetURL, options: [:]) { success in
        if success {
          result([
            "status": "opened_settings",
            "applied": false,
            "enabled": true,
            "message": "iPhone quiet mode uses notification settings and Focus.",
          ])
        } else {
          result(
            FlutterError(
              code: "QUIET_MODE_OPEN_FAILED",
              message: "Unable to open notification settings",
              details: nil
            )
          )
        }
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
    let rawPath = (args["filePath"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let rawJobName = (args["jobName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
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
      controller.showsPageRange = true

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

private extension UIApplication {
  static func preconnectTopViewController(
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
