import 'dart:async';
import 'dart:js_interop';

import 'package:chrome_extension/runtime.dart';

class WebExtensionSessionFlow {
  WebExtensionSessionFlow() {
    _messageSub = chrome.runtime.onMessage.listen(_handleMessage);
  }

  final _events = StreamController<WebExtensionSessionEvent>.broadcast();
  StreamSubscription<OnMessageEvent>? _messageSub;

  Stream<WebExtensionSessionEvent> get events => _events.stream;

  void _handleMessage(OnMessageEvent event) {
    final message = event.message;
    if (message is! Map) return;
    final type = '${message['type'] ?? ''}';
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
