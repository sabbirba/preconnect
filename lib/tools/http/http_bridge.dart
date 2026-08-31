import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:chrome_extension/runtime.dart';
import 'package:http/http.dart' as http;
import 'package:preconnect/tools/extension_bridge.dart';

class ConnectExtensionClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final completer = Completer<http.StreamedResponse>();
    final requestId =
        '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(1000000)}';
    final bodyBytes = await request.finalize().toBytes();

    StreamSubscription? subscription;
    Timer? timeoutTimer;
    subscription = chrome.runtime.onMessage.listen((event) {
      final response = decodeExtensionMessage(event.message);
      if (response == null ||
          response['type'] != 'preconnect.connectResponse' ||
          '${response['requestId']}' != requestId) {
        return;
      }
      subscription?.cancel();
      timeoutTimer?.cancel();
      final error = response['error'];
      if (error != null) {
        completer.completeError(Exception('$error'));
        return;
      }
      final rawHeaders = response['headers'];
      final headers = rawHeaders is Map
          ? rawHeaders.map(
              (key, value) => MapEntry(key.toString(), value.toString()),
            )
          : const <String, String>{};
      final encodedBody = '${response['body'] ?? ''}';
      completer.complete(
        http.StreamedResponse(
          Stream.value(
            encodedBody.isEmpty ? <int>[] : base64Decode(encodedBody),
          ),
          (response['statusCode'] as num).toInt(),
          headers: headers,
          request: request,
        ),
      );
    });

    timeoutTimer = Timer(const Duration(seconds: 30), () {
      subscription?.cancel();
      if (!completer.isCompleted) {
        completer.completeError(
          TimeoutException('Connect background request timed out'),
        );
      }
    });

    final sent = sendExtensionRuntimeMessage(<String, dynamic>{
      'type': 'preconnect.connectRequest',
      'requestId': requestId,
      'method': request.method,
      'url': request.url.toString(),
      'headers': request.headers,
      'body': base64Encode(bodyBytes),
    });
    if (!sent) {
      timeoutTimer.cancel();
      await subscription.cancel();
      throw StateError('Extension background messaging is unavailable');
    }
    return completer.future;
  }
}
