import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:chrome_extension/runtime.dart';
import 'package:preconnect/tools/runtime_web.dart';

class WebExtensionShortcutBridge {
  WebExtensionShortcutBridge({required this.onShortcut}) {
    if (!isChromeRuntimeAvailable()) return;
    _messageSub = chrome.runtime.onMessage.listen(_handleMessage);
  }

  final void Function(String action) onShortcut;
  StreamSubscription<OnMessageEvent>? _messageSub;

  void _handleMessage(OnMessageEvent event) {
    Map<String, dynamic>? resp;
    final raw = event.message;
    if (raw is String) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) resp = Map<String, dynamic>.from(decoded);
      } catch (_) {}
    } else if (raw is Map) {
      resp = Map<String, dynamic>.from(raw);
    } else {
      try {
        final dartified = (raw as JSObject).dartify();
        if (dartified is Map) resp = Map<String, dynamic>.from(dartified);
      } catch (_) {}
    }
    if (resp == null) return;
    final type = '${resp['type'] ?? ''}';
    if (type != 'preconnect.browserShortcut') return;
    final action = '${resp['shortcut'] ?? ''}'.trim();
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
