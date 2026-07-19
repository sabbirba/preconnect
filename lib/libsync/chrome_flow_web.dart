import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
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

  _safeSendMessage({
    'type': 'preconnect.startLibsyncOauth',
    'requestId': requestId,
    'oauthUrl': oauthUrl,
    'redirectUri': redirectUri,
  });

  return completer.future;
}

Future<void> openCaptivePortalFlow(String portalUrl) async {
  _safeSendMessage({
    'type': 'preconnect.startCaptivePortalFlow',
    'portalUrl': portalUrl,
  });
}

void _safeSendMessage(Map<String, dynamic> message) {
  try {
    final chromeVal = globalContext.getProperty('chrome'.toJS);
    if (chromeVal.isUndefinedOrNull) return;
    final chromeObj = chromeVal as JSObject;

    final runtimeVal = chromeObj.getProperty('runtime'.toJS);
    if (runtimeVal.isUndefinedOrNull) return;
    final runtimeObj = runtimeVal as JSObject;

    final sendMessageVal = runtimeObj.getProperty('sendMessage'.toJS);
    if (sendMessageVal.isUndefinedOrNull) return;
    final sendMessageFunc = sendMessageVal as JSFunction;

    sendMessageFunc.callAsFunction(runtimeObj, null, jsonEncode(message).toJS);
  } catch (_) {}
}
