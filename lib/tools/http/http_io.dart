import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

final http.Client _sharedClient = http.Client();

http.Client createHttpClient() => _sharedClient;

dynamic _parseJsonWorker(String source) => jsonDecode(source);

Future<dynamic> computeJsonDecode(String source) async {
  if (source.length > 50000) {
    return compute(_parseJsonWorker, source);
  }
  return jsonDecode(source);
}
