import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

Future<void> openImageInBrowser({
  required Uint8List bytes,
  required String fileName,
}) async {
  final navigator = web.window.navigator;
  final file = web.File(
    [bytes.toJS].toJS,
    fileName,
    web.FilePropertyBag(type: 'image/png'),
  );
  final shareData = web.ShareData(files: [file].toJS);

  if (navigator.canShare(shareData)) {
    try {
      await navigator.share(shareData).toDart;
      return;
    } catch (_) {}
  }

  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: 'image/png'),
  );
  final objectUrl = web.URL.createObjectURL(blob);
  try {
    final anchor = web.document.createElement('a') as web.HTMLAnchorElement
      ..href = objectUrl
      ..download = fileName;
    web.document.body?.appendChild(anchor);
    anchor.click();
    web.document.body?.removeChild(anchor);
  } finally {
    web.URL.revokeObjectURL(objectUrl);
  }
}
