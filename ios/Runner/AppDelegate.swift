import Flutter
import GoogleMobileAds
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let pendingShortcutKey = "flutter.pending_shortcut_action"
  private let adsBridge = PreconnectAdsBridge()

  private func cacheShortcutAction(_ type: String) {
    UserDefaults.standard.set(type, forKey: pendingShortcutKey)
  }

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if let shortcutItem = launchOptions?[.shortcutItem] as? UIApplicationShortcutItem {
      cacheShortcutAction(shortcutItem.type)
    }
    if let controller = window?.rootViewController as? FlutterViewController {
      registerBuildInfoChannel(binaryMessenger: controller.binaryMessenger)
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
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "PreconnectAdsBridge") {
      adsBridge.register(with: registrar)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "PreconnectBuildInfo") {
      registerBuildInfoChannel(binaryMessenger: registrar.messenger())
    }
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  private func registerBuildInfoChannel(binaryMessenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "preconnect/build_info",
      binaryMessenger: binaryMessenger
    )
    channel.setMethodCallHandler { call, result in
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
  }
}

private final class PreconnectAdsBridge: NSObject {
  private var rewardedCoordinator: RewardedCoordinator?

  func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "preconnect/ads",
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call: call, result: result)
    }
  }

  private func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "initialize":
      initialize(args: args, result: result)
    case "showRewarded":
      showRewarded(args: args, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func initialize(args: [String: Any], result: @escaping FlutterResult) {
    if let testDeviceIds = args["testDeviceIds"] as? [String], !testDeviceIds.isEmpty {
      MobileAds.shared.requestConfiguration.testDeviceIdentifiers = testDeviceIds
    }
    MobileAds.shared.start { _ in }
    result(nil)
  }

  private func showRewarded(args: [String: Any], result: @escaping FlutterResult) {
    guard let presenter = UIApplication.preconnectTopViewController() else {
      result(
        FlutterError(
          code: "ADS_REWARDED_CONTEXT",
          message: "No presenter available",
          details: nil
        )
      )
      return
    }
    let rawAdUnitId = (args["adUnitId"] as? String)?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let adUnitId = (rawAdUnitId?.isEmpty == false)
      ? rawAdUnitId!
      : Self.envAdUnitId(forKey: "REWARDED_AD_UNIT_ID")
    guard let adUnitId else {
      result(
        FlutterError(
          code: "ADS_REWARDED_CONFIG",
          message: "Missing REWARDED_AD_UNIT_ID",
          details: nil
        )
      )
      return
    }
    let nonPersonalizedAds = args["nonPersonalizedAds"] as? Bool ?? true

    let coordinator = RewardedCoordinator(
      adUnitId: adUnitId,
      nonPersonalizedAds: nonPersonalizedAds,
      presenter: presenter,
      onSuccess: { [weak self] payload in
        self?.rewardedCoordinator = nil
        result(payload)
      },
      onError: { [weak self] code, message in
        self?.rewardedCoordinator = nil
        result(FlutterError(code: code, message: message, details: nil))
      }
    )
    rewardedCoordinator = coordinator
    coordinator.loadAndShow()
  }

  private static func envAdUnitId(forKey key: String) -> String? {
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
}

private final class RewardedCoordinator: NSObject, FullScreenContentDelegate {
  private let adUnitId: String
  private let nonPersonalizedAds: Bool
  private weak var presenter: UIViewController?
  private let onSuccess: ([String: Any]) -> Void
  private let onError: (String, String) -> Void
  private var ad: RewardedAd?
  private var rewardAmount = 0
  private var rewardType = ""

  init(
    adUnitId: String,
    nonPersonalizedAds: Bool,
    presenter: UIViewController,
    onSuccess: @escaping ([String: Any]) -> Void,
    onError: @escaping (String, String) -> Void
  ) {
    self.adUnitId = adUnitId
    self.nonPersonalizedAds = nonPersonalizedAds
    self.presenter = presenter
    self.onSuccess = onSuccess
    self.onError = onError
  }

  func loadAndShow() {
    RewardedAd.load(
      with: adUnitId,
      request: Self.adRequest(nonPersonalizedAds: nonPersonalizedAds)
    ) { [weak self] ad, error in
      guard let self else { return }
      if let error {
        self.onError("ADS_REWARDED_LOAD", error.localizedDescription)
        return
      }
      guard let ad, let presenter = self.presenter else {
        self.onError("ADS_REWARDED_CONTEXT", "No presenter available")
        return
      }
      self.ad = ad
      ad.fullScreenContentDelegate = self
      ad.present(from: presenter) {
        let reward = ad.adReward
        self.rewardAmount = reward.amount.intValue
        self.rewardType = reward.type
      }
    }
  }

  private static func adRequest(nonPersonalizedAds: Bool) -> Request {
    let request = Request()
    if nonPersonalizedAds {
      let extras = Extras()
      extras.additionalParameters = ["npa": "1"]
      request.register(extras)
    }
    return request
  }

  func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
    onSuccess([
      "shown": true,
      "rewardEarned": rewardAmount > 0 || !rewardType.isEmpty,
      "amount": rewardAmount,
      "type": rewardType,
    ])
  }

  func ad(
    _ ad: FullScreenPresentingAd,
    didFailToPresentFullScreenContentWithError error: Error
  ) {
    onError("ADS_REWARDED_SHOW", error.localizedDescription)
  }
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
