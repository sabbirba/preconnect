import 'dart:convert';
import 'dart:io';
import 'package:cronet_http/cronet_http.dart';
import 'package:cupertino_http/cupertino_http.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:preconnect/tools/http/http_base.dart';

http.Client _createPlatformHttpClient() {
  try {
    if (Platform.isAndroid) {
      final engine = CronetEngine.build(
        enableQuic: true,
        enableBrotli: true,
        enableHttp2: true,
      );
      return CronetClient.fromCronetEngine(engine);
    }
    if (Platform.isIOS || Platform.isMacOS) {
      final config = URLSessionConfiguration.defaultSessionConfiguration();
      return CupertinoClient.fromSessionConfiguration(config);
    }
  } catch (_) {}
  return http.Client();
}

final http.Client _sharedPlatformClient = _createPlatformHttpClient();
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
