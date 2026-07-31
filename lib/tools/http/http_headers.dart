import 'package:flutter/foundation.dart' show kIsWeb;

Map<String, String> compressionHeaders() {
  if (kIsWeb) return const <String, String>{};
  return const <String, String>{'Accept-Encoding': 'gzip, deflate'};
}

Map<String, String> compressionHeadersForUri(Uri? uri) {
  return compressionHeaders();
}
