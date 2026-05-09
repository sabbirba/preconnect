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

    let openPdfChannel = FlutterMethodChannel(
      name: "preconnect/open_pdf",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    openPdfChannel.setMethodCallHandler { call, result in
      switch call.method {
      case "openPdf":
        guard
          let args = call.arguments as? [String: Any],
          let rawPath = args["filePath"] as? String
        else {
          result(FlutterError(
            code: "INVALID_PATH",
            message: "Missing file path",
            details: nil))
          return
        }

        let path = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else {
          result(FlutterError(
            code: "INVALID_PATH",
            message: "Missing file path",
            details: nil))
          return
        }

        guard FileManager.default.fileExists(atPath: path) else {
          result(FlutterError(
            code: "FILE_NOT_FOUND",
            message: "Selected PDF file was not found",
            details: nil))
          return
        }

        let fileURL = URL(fileURLWithPath: path)
        result(NSWorkspace.shared.open(fileURL))
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
