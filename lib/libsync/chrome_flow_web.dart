import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:math';
import 'package:chrome_extension/runtime.dart';

Future<String?> openChromeExtensionOAuthFlow(
  String oauthUrl,
  String redirectUri,
) async {
  final completer = Completer<String?>();
  final requestId =
      '${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(1000000)}';

  StreamSubscription? subscription;
  subscription = chrome.runtime.onMessage.listen((event) {
    Map<String, dynamic>? resp;
    final raw = event.message;
    if (raw is String) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) resp = Map<String, dynamic>.from(decoded);
      } catch (_) {}
    } else if (raw is Map) {
      resp = Map<String, dynamic>.from(raw);
    } else if (raw != null && raw.isA<JSObject>()) {
      try {
        final dartified = (raw as JSObject).dartify();
        if (dartified is Map) resp = Map<String, dynamic>.from(dartified);
      } catch (_) {}
    }
    if (resp == null) return;
    if (resp['type'] != 'preconnect.libsyncOauthResponse') return;
    if ('${resp['requestId']}' != requestId) return;
    subscription?.cancel();
    if (resp.containsKey('error')) {
      completer.complete(null);
    } else {
      completer.complete('${resp['code'] ?? ''}');
    }
  });

  await chrome.runtime.sendMessage(
    null,
    jsonEncode({
      'type': 'preconnect.startLibsyncOauth',
      'requestId': requestId,
      'oauthUrl': oauthUrl,
      'redirectUri': redirectUri,
    }).toJS,
    null,
  );

  return completer.future;
}

Future<void> openCaptivePortalFlow(String portalUrl) async {
  await chrome.runtime.sendMessage(
    null,
    jsonEncode({
      'type': 'preconnect.startCaptivePortalFlow',
      'portalUrl': portalUrl,
    }).toJS,
    null,
  );
}
