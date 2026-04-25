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

  if (!navigator.canShare(shareData)) {
    throw UnsupportedError('Sharing images is not supported in this browser.');
  }

  await navigator.share(shareData).toDart;
}
