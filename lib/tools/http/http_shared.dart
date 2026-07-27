import 'dart:convert';
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

final http.Client _sharedHttpClient = http.Client();
final http.Client _sharedLoggingClient = LoggingClient(_sharedHttpClient);

http.Client createHttpClient() {
  return _sharedLoggingClient;
}

Future<dynamic> computeJsonDecode(String source) async {
  return jsonDecode(source);
}
