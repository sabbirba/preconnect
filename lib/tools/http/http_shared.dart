import 'package:http/http.dart' as http;
import 'package:preconnect/tools/app_log.dart';

class LoggingClient extends http.BaseClient {
  LoggingClient(this._inner);
  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final startTime = DateTime.now();
    AppLog.write('HTTP Request: ${request.method} ${request.url}');
    try {
      final response = await _inner.send(request);
      final duration = DateTime.now().difference(startTime).inMilliseconds;
      AppLog.write(
        'HTTP Response: ${request.method} ${request.url} -> Status ${response.statusCode} (${duration}ms) Length: ${response.contentLength}',
      );
      return response;
    } catch (e) {
      final duration = DateTime.now().difference(startTime).inMilliseconds;
      AppLog.write(
        'HTTP Error: ${request.method} ${request.url} -> Exception: $e (${duration}ms)',
      );
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
