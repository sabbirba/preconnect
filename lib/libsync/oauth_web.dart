import 'dart:async';
import 'package:web/web.dart' as web;
import 'package:preconnect/tools/polling_timer.dart';
import 'dart:js_interop';
import 'error_reporter.dart';

extension type OAuthMessageData._(JSObject _) implements JSObject {
  external String? get type;
  external String? get code;
}

Future<String?> openWebOAuthFlow(String oauthUrl, String redirectUri) async {
  final width = 500;
  final height = 600;
  final left = (web.window.screen.width - width) / 2;
  final top = (web.window.screen.height - height) / 2;

  final popup = web.window.open(
    oauthUrl,
    'Google Sign In',
    'width=$width,height=$height,top=$top,left=$left,status=no,resizable=yes',
  );

  if (popup == null) {
    return null;
  }

  final completer = Completer<String?>();

  void Function(web.MessageEvent)? dartListener;

  dartListener = (web.MessageEvent event) {
    final data = event.data;
    if (data != null && data.isA<JSObject>()) {
      try {
        final msg = OAuthMessageData._(data as JSObject);
        if (msg.type == 'PRECONNECT_AUTH_CODE') {
          final codeVal = msg.code;
          if (codeVal != null && !completer.isCompleted) {
            completer.complete(codeVal);
          }
        }
      } catch (error, stackTrace) {
        reportLibSyncError(
          'Reading the LibSync OAuth response',
          error,
          stackTrace,
        );
      }
    }
  };

  final eventListener = dartListener.toJS;
  web.window.addEventListener('message', eventListener);

  final timer = PollingTimer(const Duration(milliseconds: 500), (t) {
    if (popup.closed) {
      t.cancel();
      if (!completer.isCompleted) {
        completer.complete(null);
      }
    }
  });

  final result = await completer.future;
  timer.cancel();
  web.window.removeEventListener('message', eventListener);
  return result;
}
