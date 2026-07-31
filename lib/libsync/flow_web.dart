import 'dart:async';
import 'dart:math';
import 'package:chrome_extension/runtime.dart';
import 'package:preconnect/tools/extension_bridge.dart';

Future<String?> openChromeExtensionOAuthFlow(
  String oauthUrl,
  String redirectUri,
) async {
  final completer = Completer<String?>();
  final requestId =
      '${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(1000000)}';

  StreamSubscription? subscription;
  Timer? timeoutTimer;
  subscription = chrome.runtime.onMessage.listen((event) {
    final resp = decodeExtensionMessage(event.message);
    if (resp == null) return;
    if (resp['type'] != 'preconnect.libsyncOauthResponse') return;
    if ('${resp['requestId']}' != requestId) return;
    subscription?.cancel();
    timeoutTimer?.cancel();
    if (resp.containsKey('error')) {
      completer.complete(null);
    } else if (resp.containsKey('tokens')) {
      completer.complete('${resp['tokens'] ?? ''}');
    } else {
      completer.complete('${resp['code'] ?? ''}');
    }
  });
  timeoutTimer = Timer(const Duration(minutes: 2), () {
    subscription?.cancel();
    if (!completer.isCompleted) completer.complete(null);
  });

  final sent = sendExtensionRuntimeMessage({
    'type': 'preconnect.startLibsyncOauth',
    'requestId': requestId,
    'oauthUrl': oauthUrl,
    'redirectUri': redirectUri,
  });
  if (!sent) {
    timeoutTimer.cancel();
    await subscription.cancel();
    return null;
  }

  return completer.future;
}

Future<void> openCaptivePortalFlow(String portalUrl) async {
  sendExtensionRuntimeMessage({
    'type': 'preconnect.startCaptivePortalFlow',
    'portalUrl': portalUrl,
  });
}
