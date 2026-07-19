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
    if (resp['type'] != 'preconnect.libsyncOauthResponse') return;
    if ('${resp['requestId']}' != requestId) return;
    subscription?.cancel();
    if (resp.containsKey('error')) {
      completer.complete(null);
    } else if (resp.containsKey('tokens')) {
      completer.complete('${resp['tokens'] ?? ''}');
    } else {
      completer.complete('${resp['code'] ?? ''}');
    }
  });

  try {
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
  } catch (_) {}

  return completer.future;
}

Future<void> openCaptivePortalFlow(String portalUrl) async {
  try {
    await chrome.runtime.sendMessage(
      null,
      jsonEncode({
        'type': 'preconnect.startCaptivePortalFlow',
        'portalUrl': portalUrl,
      }).toJS,
      null,
    );
  } catch (_) {}
}
