import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class LoggingClient extends http.BaseClient {
  LoggingClient(this._inner);
  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    try {
      return await _inner.send(request);
    } catch (_) {
      rethrow;
    }
  }

  @override
  void close() {
    _inner.close();
  }
}

http.Client createHttpClient() {
  return LoggingClient(http.Client());
}

dynamic _parseJsonWorker(String source) => jsonDecode(source);

Future<dynamic> computeJsonDecode(String source) async {
  if (source.length > 50000) {
    return compute(_parseJsonWorker, source);
  }
  return jsonDecode(source);
}
