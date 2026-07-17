import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
    override func awakeFromNib() {
        let flutterViewController = FlutterViewController()
        let windowFrame = self.frame
        self.contentViewController = flutterViewController
        self.setFrame(windowFrame, display: true)

        let messenger = flutterViewController.engine.binaryMessenger

        let buildInfoChannel = FlutterMethodChannel(
            name: "preconnect/build_info",
            binaryMessenger: messenger)
        buildInfoChannel.setMethodCallHandler { call, result in
            switch call.method {
            case "getBuildInfo":
                result([
                    "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
                        as? String ?? "",
                    "buildNumber": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion")
                        as? String ?? "",
                ])
            default:
                result(FlutterMethodNotImplemented)
            }
        }

        let quietChannel = FlutterMethodChannel(
            name: "preconnect/quiet_mode",
            binaryMessenger: messenger)
        quietChannel.setMethodCallHandler { call, result in
            switch call.method {
            case "setQuietMode":
                let args = call.arguments as? [String: Any] ?? [:]
                let enabled = args["enabled"] as? Bool ?? false
                let rawWindows = args["windows"] as? [[String: Any]] ?? []
                QuietModeSchedulerMacOS.shared.handleSetQuietMode(
                    enabled: enabled,
                    windows: rawWindows
                ) { response in
                    result(response)
                }
            case "openQuietModeSettings":
                NSWorkspace.shared.open(
                    URL(string: "x-apple.systempreferences:com.apple.preference.notifications")
                        ?? URL(string: "x-apple.systempreferences:")!)
                result([
                    "status": "opened_settings",
                    "applied": false,
                    "enabled": true,
                    "message": "Opened Focus/Notification settings.",
                ])
            default:
                result(FlutterMethodNotImplemented)
            }
        }

        let bgPermChannel = FlutterMethodChannel(
            name: "preconnect/background_permission",
            binaryMessenger: messenger)
        bgPermChannel.setMethodCallHandler { call, result in
            switch call.method {
            case "getBackgroundRefreshStatus":
                result("allowed")
            case "openBackgroundSettings":
                NSWorkspace.shared.open(
                    URL(string: "x-apple.systempreferences:")!)
                result(true)
            default:
                result(FlutterMethodNotImplemented)
            }
        }

        RegisterGeneratedPlugins(registry: flutterViewController)

        super.awakeFromNib()
    }
}
