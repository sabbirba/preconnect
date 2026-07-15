import 'dart:async';
import 'dart:js_interop';

import 'package:chrome_extension/runtime.dart';
import 'package:preconnect/tools/runtime_web.dart';

class WebExtensionLoginFlow {
  WebExtensionLoginFlow() {
    if (!isChromeRuntimeAvailable()) return;
    _messageSub = chrome.runtime.onMessage.listen(_handleMessage);
  }

  final _events = StreamController<WebExtensionLoginState>.broadcast();
  StreamSubscription<OnMessageEvent>? _messageSub;

  Stream<WebExtensionLoginState> get events => _events.stream;

  void _handleMessage(OnMessageEvent event) {
    final message = event.message;
    if (message is! Map) return;
    final type = '${message['type'] ?? ''}';
    if (type == 'preconnect.loginStarted') {
      _events.add(const WebExtensionLoginState.started());
      _ack(event);
      return;
    }
    if (type == 'preconnect.loginComplete') {
      _events.add(const WebExtensionLoginState.complete());
      _ack(event);
      return;
    }
    if (type == 'preconnect.loginFailed') {
      _events.add(WebExtensionLoginState.failed('${message['error'] ?? ''}'));
      _ack(event);
    }
  }

  void _ack(OnMessageEvent event) {
    try {
      event.sendResponse.callAsFunction(null, {'ok': true}.jsify());
    } catch (_) {}
  }

  Future<void> start() async {
    await chrome.runtime.sendMessage(null, {
      'type': 'preconnect.startLogin',
    }, null);
  }

  Future<void> dispose() async {
    await _messageSub?.cancel();
    await _events.close();
  }
}

class WebExtensionLoginState {
  const WebExtensionLoginState.started()
    : type = WebExtensionLoginStateKind.started,
      message = null;
  const WebExtensionLoginState.complete()
    : type = WebExtensionLoginStateKind.complete,
      message = null;
  const WebExtensionLoginState.failed(this.message)
    : type = WebExtensionLoginStateKind.failed;

  final WebExtensionLoginStateKind type;
  final String? message;

  bool get isStarted => type == WebExtensionLoginStateKind.started;
  bool get isComplete => type == WebExtensionLoginStateKind.complete;
  bool get isFailed => type == WebExtensionLoginStateKind.failed;
}

enum WebExtensionLoginStateKind { started, complete, failed }
