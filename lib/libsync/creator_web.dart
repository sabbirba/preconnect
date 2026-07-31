import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:chrome_extension/runtime.dart';
import 'package:preconnect/tools/runtime_stub.dart'
    if (dart.library.js_interop) 'package:preconnect/tools/runtime_web.dart';
import 'package:preconnect/tools/extension_bridge.dart';

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
      Timer? timeoutTimer;
      subscription = chrome.runtime.onMessage.listen((event) {
        final resp = decodeExtensionMessage(event.message);
        if (resp == null) return;
        if (resp['type'] != 'preconnect.libsyncResponse') return;
        if ('${resp['requestId']}' != requestId) return;
        subscription?.cancel();
        timeoutTimer?.cancel();
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
      timeoutTimer = Timer(const Duration(seconds: 30), () {
        subscription?.cancel();
        if (!completer.isCompleted) {
          completer.completeError(
            TimeoutException('Browser extension request timed out.'),
          );
        }
      });

      final sent = sendExtensionRuntimeMessage(<String, dynamic>{
        'type': 'preconnect.libsyncRequest',
        'requestId': requestId,
        'method': request.method,
        'url': request.url.toString(),
        'headers': jsonEncode(request.headers),
        'body': base64Encode(bodyBytes),
      });
      if (!sent) {
        timeoutTimer.cancel();
        await subscription.cancel();
        throw StateError('Browser extension messaging is unavailable.');
      }

      return completer.future;
    }

    return _webFallbackClient.send(request);
  }
}

final http.Client _webFallbackClient = http.Client();
final ExtensionHttpClient _sharedExtensionClient = ExtensionHttpClient();

http.Client createLibSyncClient() => _sharedExtensionClient;
