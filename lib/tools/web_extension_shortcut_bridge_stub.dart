class WebExtensionShortcutBridge {
  WebExtensionShortcutBridge({required void Function(String action) onShortcut});

  Future<void> dispose() async {}
}
