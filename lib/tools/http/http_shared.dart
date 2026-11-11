import 'package:http/http.dart' as http;
import 'package:http/browser_client.dart';

import 'package:preconnect/tools/http/http_bridge.dart';
import 'package:preconnect/tools/runtime_stub.dart'
    if (dart.library.js_interop) 'package:preconnect/tools/runtime_web.dart';

http.Client createHttpClient() {
  return _BrowserHttpClient();
}

class _BrowserHttpClient extends http.BaseClient {
  final BrowserClient _defaultClient = BrowserClient();
  final BrowserClient _authClient = BrowserClient()..withCredentials = true;
  final ConnectExtensionClient _extensionClient = ConnectExtensionClient();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (request.url.host == 'connect.bracu.ac.bd') {
      if (isChromeRuntimeAvailable()) {
        return _sendFromExtension(request);
      }
      return _authClient.send(request);
    }
    return _defaultClient.send(request);
  }

  Future<http.StreamedResponse> _sendFromExtension(
    http.BaseRequest request,
  ) async {
    final body = await request.finalize().toBytes();
    final direct = await _sendDirect(_copy(request, body));
    if (direct != null) return direct;
    return _extensionClient.send(_copy(request, body));
  }

  Future<http.StreamedResponse?> _sendDirect(http.Request request) async {
    try {
      final response = await _defaultClient.send(request);
      if (response.statusCode == 401 || response.statusCode == 403) {
        return null;
      }
      return response;
    } on http.ClientException {
      return null;
    }
  }

  http.Request _copy(http.BaseRequest request, List<int> body) {
    return http.Request(request.method, request.url)
      ..headers.addAll(request.headers)
      ..followRedirects = request.followRedirects
      ..bodyBytes = body;
  }

  @override
  void close() {
    _defaultClient.close();
    _authClient.close();
    _extensionClient.close();
  }
}
