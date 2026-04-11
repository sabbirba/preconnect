import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    let buildInfoChannel = FlutterMethodChannel(
      name: "preconnect/build_info",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
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

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
