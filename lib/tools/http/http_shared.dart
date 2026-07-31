import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:preconnect/tools/http/http_base.dart';

http.Client createHttpClient() {
  return createSharedHttpClient();
}

Future<dynamic> computeJsonDecode(String source) async {
  return jsonDecode(source);
}
