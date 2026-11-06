import 'dart:convert';

import 'package:flutter/foundation.dart';

dynamic _decodeJson(String source) => jsonDecode(source);

Future<dynamic> computeJsonDecode(String source) async {
  if (source.length > 50000) {
    return compute(_decodeJson, source);
  }
  return jsonDecode(source);
}
