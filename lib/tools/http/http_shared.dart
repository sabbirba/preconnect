import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/browser_client.dart';
import 'package:preconnect/tools/http/http_base.dart';
import 'package:preconnect/tools/http/http_bridge.dart';

http.Client createHttpClient() {
  return DelegatingHttpClient(_BrowserHttpClient());
}

class _BrowserHttpClient extends http.BaseClient {
  final BrowserClient _defaultClient = BrowserClient();
  final ConnectExtensionClient _bracuClient = ConnectExtensionClient();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (request.url.host == 'connect.bracu.ac.bd') {
      return _bracuClient.send(request);
    }
    return _defaultClient.send(request);
  }

  @override
  void close() {
    _defaultClient.close();
    _bracuClient.close();
  }
}

Future<dynamic> computeJsonDecode(String source) async {
  return jsonDecode(source);
}
