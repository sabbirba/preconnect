import 'dart:convert';
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
        return _extensionClient.send(request);
      }
      return _authClient.send(request);
    }
    return _defaultClient.send(request);
  }

  @override
  void close() {
    _defaultClient.close();
    _authClient.close();
    _extensionClient.close();
  }
}

Future<dynamic> computeJsonDecode(String source) async {
  return jsonDecode(source);
}
