import Flutter
import Foundation
import NetworkExtension
import SystemConfiguration.CaptiveNetwork
import UIKit

final class IosNetworkAssist {
    static func register(binaryMessenger: FlutterBinaryMessenger) {
        let channel = FlutterMethodChannel(
            name: "preconnect/ios_network_assist",
            binaryMessenger: binaryMessenger
        )
        channel.setMethodCallHandler { call, result in
            switch call.method {
            case "getCurrentSsid":
                IosNetworkAssist.getCurrentSsid(result: result)
            case "openWifiSettings":
                IosNetworkAssist.openWifiSettings(result: result)
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }

    private static func getCurrentSsid(result: @escaping FlutterResult) {
        if #available(iOS 14.0, *) {
            NEHotspotNetwork.fetchCurrent { network in
                DispatchQueue.main.async {
                    if let ssid = network?.ssid, !ssid.isEmpty {
                        result(ssid)
                    } else {
                        let legacy = legacySsid()
                        result(legacy?.isEmpty == false ? legacy : nil)
                    }
                }
            }
        } else {
            let ssid = legacySsid()
            result(ssid?.isEmpty == false ? ssid : nil)
        }
    }

    private static func legacySsid() -> String? {
        guard let interfaces = CNCopySupportedInterfaces() as? [String] else {
            return nil
        }
        for interface in interfaces {
            guard
                let info = CNCopyCurrentNetworkInfo(interface as CFString) as? [String: Any],
                let ssid = info[kCNNetworkInfoKeySSID as String] as? String,
                !ssid.isEmpty
            else { continue }
            return ssid
        }
        return nil
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
