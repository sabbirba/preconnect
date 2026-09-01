import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:preconnect/tools/http/http_base.dart';

final http.Client _sharedPlatformClient = http.Client();
final http.Client _sharedDelegatingClient = DelegatingHttpClient(
  _sharedPlatformClient,
);

http.Client createHttpClient() {
  return _sharedDelegatingClient;
}

dynamic _parseJsonWorker(String source) => jsonDecode(source);

Future<dynamic> computeJsonDecode(String source) async {
  if (source.length > 50000) {
    return compute(_parseJsonWorker, source);
  }
  return jsonDecode(source);
}
