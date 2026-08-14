import Flutter
import Foundation
import UIKit

final class IosNetworkAssist {
  static func register(binaryMessenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "preconnect/ios_network_assist",
      binaryMessenger: binaryMessenger
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "openWifiSettings":
        IosNetworkAssist.openWifiSettings(result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private static func openWifiSettings(result: @escaping FlutterResult) {
    DispatchQueue.main.async {
      var candidates: [URL] = []
      if let wifiURL = URL(string: "App-Prefs:WIFI") {
        candidates.append(wifiURL)
      }
      if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
        candidates.append(settingsURL)
      }
      guard let target = candidates.first(where: { UIApplication.shared.canOpenURL($0) }) else {
        result(false)
        return
      }
      UIApplication.shared.open(target, options: [:]) { success in
        result(success)
      }
    }
  }
}
