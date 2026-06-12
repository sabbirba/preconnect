import 'dart:async';
import 'dart:js_interop';

import 'package:chrome_extension/runtime.dart';

class WebExtensionShortcutBridge {
  WebExtensionShortcutBridge({required this.onShortcut}) {
    if (!_isChromeRuntimeAvailable()) return;
    _messageSub = chrome.runtime.onMessage.listen(_handleMessage);
  }

  final void Function(String action) onShortcut;
  StreamSubscription<OnMessageEvent>? _messageSub;

  void _handleMessage(OnMessageEvent event) {
    final message = event.message;
    if (message is! Map) return;
    final type = '${message['type'] ?? ''}';
    if (type != 'preconnect.browserShortcut') return;
    final action = '${message['shortcut'] ?? ''}'.trim();
    if (action.isEmpty) return;
    onShortcut(action);
    try {
      event.sendResponse.callAsFunction(null, {'ok': true}.jsify());
    } catch (_) {}
  }

  Future<void> dispose() async {
    await _messageSub?.cancel();
  }
}

bool _isChromeRuntimeAvailable() {
  try {
    return chrome.runtime.isAvailable && Uri.base.scheme == 'chrome-extension';
  } catch (_) {
    return false;
  }
}
