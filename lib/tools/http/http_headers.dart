import 'package:flutter/foundation.dart' show kIsWeb;

final RegExp _httpEtagPattern = RegExp(r'^(?:W/)?"[\x21\x23-\x7E\x80-\xFF]*"$');

bool isValidHttpEtag(String? value) {
  if (value == null || value.length > 1024) return false;
  return _httpEtagPattern.hasMatch(value);
}

Map<String, String> compressionHeaders() {
  if (kIsWeb) return const <String, String>{};
  return const <String, String>{'Accept-Encoding': 'gzip, deflate'};
}

Map<String, String> compressionHeadersForUri(Uri? uri) {
  return compressionHeaders();
}
