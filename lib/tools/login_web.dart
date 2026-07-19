import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:chrome_extension/runtime.dart';
import 'package:chrome_extension/tabs.dart' as ext_tabs;
import 'package:preconnect/tools/extension_config.dart';
import 'package:preconnect/tools/pkce.dart';
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
    if (Uri.base.scheme == 'moz-extension') {
      await _startFirefox(idp: idp);
      return;
    }
    try {
      final message = <String, dynamic>{'type': 'preconnect.startLogin'};
      if (idp != null) message['idp'] = idp;
      await chrome.runtime.sendMessage(null, jsonEncode(message).toJS, null);
    } catch (_) {}
  }

  Future<void> _startFirefox({String? idp}) async {
    try {
      final verifier = generatePkceVerifier();
      final challenge = codeChallengeS256(verifier);
      var authUrl = WebExtensionApiConfig.authUrlWithPkce(challenge);
      if (idp != null && idp.isNotEmpty) {
        try {
          final parsed = Uri.parse(authUrl);
          authUrl = parsed
              .replace(
                queryParameters: {
                  ...parsed.queryParameters,
                  'kc_idp_hint': idp,
                },
              )
              .toString();
        } catch (_) {}
      }

      final tab = await ext_tabs.chrome.tabs.create(
        ext_tabs.CreateProperties(url: authUrl, active: true),
      );

      if (tab.id == null) {
        _events.add(
          const WebExtensionLoginState.failed(
            'Firefox: unable to open login tab.',
          ),
        );
        return;
      }

      _events.add(const WebExtensionLoginState.started());

      try {
        await chrome.runtime.sendMessage(
          null,
          jsonEncode({
            'type': 'preconnect.loginTabCreated',
            'tabId': tab.id,
            'verifier': verifier,
          }).toJS,
          null,
        );
      } catch (_) {}
    } catch (e) {
      _events.add(
        WebExtensionLoginState.failed('Firefox login error: $e'),
      );
    }
  }

  Future<void> logout() async {
    try {
      await chrome.runtime.sendMessage(
        null,
        jsonEncode(<String, dynamic>{'type': 'preconnect.startLogout'}).toJS,
        null,
      );
    } catch (_) {}
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
