import Flutter
import UIKit
import WidgetKit

class SceneDelegate: FlutterSceneDelegate {
  private static let appGroupIdentifier = "group.com.sabbirba.preconnect"
  private let pendingShortcutKey = "flutter.pending_shortcut_action"

  private func cacheShortcutAction(_ type: String) {
    guard let defaults = UserDefaults(suiteName: Self.appGroupIdentifier) else {
      UserDefaults.standard.set(type, forKey: pendingShortcutKey)
      return
    }
    defaults.set(type, forKey: pendingShortcutKey)
    if #available(iOS 14.0, *) {
      WidgetCenter.shared.reloadAllTimelines()
    }
  }

  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    if let shortcutItem = connectionOptions.shortcutItem {
      cacheShortcutAction(shortcutItem.type)
    }
    super.scene(scene, willConnectTo: session, options: connectionOptions)
  }

  override func windowScene(
    _ windowScene: UIWindowScene,
    performActionFor shortcutItem: UIApplicationShortcutItem,
    completionHandler: @escaping (Bool) -> Void
  ) {
    cacheShortcutAction(shortcutItem.type)
    completionHandler(true)
  }
}
