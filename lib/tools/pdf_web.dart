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

  void revoke() => web.URL.revokeObjectURL(objectUrl);

  try {
    web.window.open(objectUrl, '_blank');
    web.window.addEventListener(
      'focus',
      (() => revoke()).toJS,
      {'once': true}.jsify() as JSAny,
    );
  } catch (_) {
    web.window.location.assign(objectUrl);
  }
}
