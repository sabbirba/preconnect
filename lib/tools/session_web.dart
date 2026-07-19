import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:chrome_extension/runtime.dart';
import 'package:preconnect/tools/runtime_web.dart';

class WebExtensionSessionFlow {
  WebExtensionSessionFlow() {
    if (!isChromeRuntimeAvailable()) return;
    _messageSub = chrome.runtime.onMessage.listen(_handleMessage);
  }

  final _events = StreamController<WebExtensionSessionEvent>.broadcast();
  StreamSubscription<OnMessageEvent>? _messageSub;

  Stream<WebExtensionSessionEvent> get events => _events.stream;

  void _handleMessage(OnMessageEvent event) {
    Map<String, dynamic>? resp;
    final dartified = (event.message as JSAny?)?.dartify();
    if (dartified is String) {
      try {
        final decoded = jsonDecode(dartified);
        if (decoded is Map) resp = Map<String, dynamic>.from(decoded);
      } catch (_) {}
    } else if (dartified is Map) {
      resp = Map<String, dynamic>.from(dartified);
    }
    if (resp == null) return;
    final type = '${resp['type'] ?? ''}';
    if (type == 'preconnect.logoutComplete') {
      _events.add(const WebExtensionSessionEvent.logoutComplete());
      try {
        event.sendResponse.callAsFunction(null, {'ok': true}.jsify());
      } catch (_) {}
    }
  }

  Future<void> dispose() async {
    await _messageSub?.cancel();
    await _events.close();
  }
}

class WebExtensionSessionEvent {
  const WebExtensionSessionEvent.logoutComplete()
    : type = WebExtensionSessionEventKind.logoutComplete;

  final WebExtensionSessionEventKind type;
}

enum WebExtensionSessionEventKind { logoutComplete }
