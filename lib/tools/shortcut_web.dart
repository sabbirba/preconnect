import 'dart:async';

import 'package:chrome_extension/runtime.dart';
import 'package:preconnect/tools/extension_bridge.dart';
import 'package:preconnect/tools/runtime_web.dart';

class WebExtensionShortcutBridge {
  WebExtensionShortcutBridge({required this.onShortcut}) {
    if (!isChromeRuntimeAvailable()) return;
    _messageSub = chrome.runtime.onMessage.listen(_handleMessage);
  }

  final void Function(String action) onShortcut;
  StreamSubscription<OnMessageEvent>? _messageSub;

  void _handleMessage(OnMessageEvent event) {
    final resp = decodeExtensionMessage(event.message);
    if (resp == null) return;
    final type = '${resp['type'] ?? ''}';
    if (type != 'preconnect.browserShortcut') return;
    final action = '${resp['shortcut'] ?? ''}'.trim();
    if (action.isEmpty) return;
    onShortcut(action);
    acknowledgeExtensionMessage(event);
  }

  Future<void> dispose() async {
    await _messageSub?.cancel();
  }
}
