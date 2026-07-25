import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:chrome_extension/runtime.dart';
import 'package:preconnect/tools/runtime_stub.dart'
    if (dart.library.js_interop) 'package:preconnect/tools/runtime_web.dart';

import 'package:preconnect/libsync/libsync_client.dart';

class ExtensionHttpClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (isChromeRuntimeAvailable()) {
      final completer = Completer<http.StreamedResponse>();
      final requestId =
          '${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(1000000)}';

      List<int> bodyBytes = [];
      if (request is http.Request) {
        bodyBytes = request.bodyBytes;
      } else {
        final byteStream = request.finalize();
        bodyBytes = await byteStream.toBytes();
      }

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
        if (resp['type'] != 'preconnect.libsyncResponse') return;
        if ('${resp['requestId']}' != requestId) return;
        subscription?.cancel();
        if (resp.containsKey('error')) {
          completer.completeError(Exception(resp['error']));
        } else {
          final statusCode = (resp['statusCode'] as num).toInt();
          final respHeaders = resp['headers'];
          Map<String, String> headers = const <String, String>{};
          if (respHeaders is Map) {
            headers = respHeaders.map(
              (k, v) => MapEntry(k.toString(), v.toString()),
            );
          }
          final bodyBase64 = '${resp['body'] ?? ''}';
          final respBodyBytes = bodyBase64.isEmpty
              ? <int>[]
              : base64Decode(bodyBase64);

          final cookiesMap = resp['cookies'];
          if (cookiesMap is Map) {
            final cookiesToSave = cookiesMap.map(
              (k, v) => MapEntry(k.toString(), v.toString()),
            );
            unawaited(LibSyncApiClient().saveCookies(cookiesToSave));
          }

          completer.complete(
            http.StreamedResponse(
              Stream.value(respBodyBytes),
              statusCode,
              headers: headers,
              request: request,
            ),
          );
        }
      });

      _safeSendMessage(<String, dynamic>{
        'type': 'preconnect.libsyncRequest',
        'requestId': requestId,
        'method': request.method,
        'url': request.url.toString(),
        'headers': jsonEncode(request.headers),
        'body': base64Encode(bodyBytes),
      });

      return completer.future;
    }

    return http.Client().send(request);
  }
}

void _safeSendMessage(Map<String, dynamic> message) {
  try {
    var extensionObj = globalContext.getProperty('chrome'.toJS);
    if (extensionObj.isUndefinedOrNull) {
      extensionObj = globalContext.getProperty('browser'.toJS);
    }
    if (extensionObj.isUndefinedOrNull) return;
    final extJSObj = extensionObj as JSObject;

    final runtimeVal = extJSObj.getProperty('runtime'.toJS);
    if (runtimeVal.isUndefinedOrNull) return;
    final runtimeObj = runtimeVal as JSObject;

    final sendMessageVal = runtimeObj.getProperty('sendMessage'.toJS);
    if (sendMessageVal.isUndefinedOrNull) return;
    final sendMessageFunc = sendMessageVal as JSFunction;

    sendMessageFunc.callAsFunction(runtimeObj, jsonEncode(message).toJS);
  } catch (_) {}
}

http.Client createLibSyncClient() => ExtensionHttpClient();
