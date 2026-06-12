import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

Future<void> openPdfInBrowser({
  required Uint8List bytes,
  required String fileName,
}) async {
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: 'application/pdf'),
  );
  final objectUrl = web.URL.createObjectURL(blob);
  try {
    web.window.open(objectUrl, '_blank');
  } catch (_) {
    web.window.location.assign(objectUrl);
    return;
  }
  Timer(const Duration(seconds: 15), () => web.URL.revokeObjectURL(objectUrl));
}
