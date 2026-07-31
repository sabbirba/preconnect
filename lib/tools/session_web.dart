import 'dart:async';

import 'package:chrome_extension/runtime.dart';
import 'package:preconnect/tools/extension_bridge.dart';
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
    final resp = decodeExtensionMessage(event.message);
    if (resp == null) return;
    final type = '${resp['type'] ?? ''}';
    if (type == 'preconnect.logoutComplete') {
      _events.add(const WebExtensionSessionEvent.logoutComplete());
      acknowledgeExtensionMessage(event);
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
