import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:chrome_extension/runtime.dart';
import 'package:preconnect/tools/runtime_stub.dart'
    if (dart.library.js_interop) 'package:preconnect/tools/runtime_web.dart';

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

      await chrome.runtime.sendMessage(
        null,
        jsonEncode(<String, dynamic>{
          'type': 'preconnect.libsyncRequest',
          'requestId': requestId,
          'method': request.method,
          'url': request.url.toString(),
          'headers': jsonEncode(request.headers),
          'body': base64Encode(bodyBytes),
        }).toJS,
        null,
      );

      return completer.future;
    }

    return http.Client().send(request);
  }
}

http.Client createLibSyncClient() => ExtensionHttpClient();
