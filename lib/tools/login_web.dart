import 'dart:async';
import 'dart:convert';
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
      _events.add(WebExtensionLoginState.failed('${resp['error'] ?? ''}'));
      _ack(event);
    }
  }

  void _ack(OnMessageEvent event) {
    try {
      event.sendResponse.callAsFunction(null, {'ok': true}.jsify());
    } catch (_) {}
  }

  Future<void> start({String? idp}) async {
    final message = <String, dynamic>{'type': 'preconnect.startLogin'};
    if (idp != null) {
      message['idp'] = idp;
    }
    await chrome.runtime.sendMessage(null, jsonEncode(message).toJS, null);
  }

  Future<void> logout() async {
    await chrome.runtime.sendMessage(
      null,
      jsonEncode(<String, dynamic>{'type': 'preconnect.startLogout'}).toJS,
      null,
    );
  }

  Future<void> dispose() async {
    await _messageSub?.cancel();
    await _events.close();
  }
}

class WebExtensionLoginState {
  const WebExtensionLoginState.started()
    : type = WebExtensionLoginStateKind.started,
      error = '';

  const WebExtensionLoginState.complete()
    : type = WebExtensionLoginStateKind.complete,
      error = '';

  const WebExtensionLoginState.failed(this.error)
    : type = WebExtensionLoginStateKind.failed;

  final WebExtensionLoginStateKind type;
  final String error;

  bool get isStarted => type == WebExtensionLoginStateKind.started;
  bool get isComplete => type == WebExtensionLoginStateKind.complete;
  bool get isFailed => type == WebExtensionLoginStateKind.failed;
}

enum WebExtensionLoginStateKind { started, complete, failed }
