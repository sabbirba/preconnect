import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  private func cacheShortcutAction(_ type: String) {
    UserDefaults.standard.set(type, forKey: preconnectPendingShortcutActionKey)
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
