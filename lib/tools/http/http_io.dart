import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:preconnect/tools/http/http_base.dart';

http.Client createHttpClient() {
  return createSharedHttpClient();
}

dynamic _parseJsonWorker(String source) => jsonDecode(source);

Future<dynamic> computeJsonDecode(String source) async {
  if (source.length > 50000) {
    return compute(_parseJsonWorker, source);
  }
  return jsonDecode(source);
}
