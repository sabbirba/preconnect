// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:async';
import 'dart:html' as html;

Future<String?> pickQrFromSystemImage() async {
  final input = html.FileUploadInputElement()..accept = 'image/*';
  final change = Completer<void>();
  input.onChange.first.then((_) {
    if (!change.isCompleted) change.complete();
  });
  input.click();
  await change.future;

  final file = input.files?.isNotEmpty == true ? input.files!.first : null;
  if (file == null) return null;

  final reader = html.FileReader();
  final readDone = Completer<void>();
  reader.onLoad.first.then((_) {
    if (!readDone.isCompleted) readDone.complete();
  });
  reader.onError.first.then((_) {
    if (!readDone.isCompleted) {
      readDone.completeError(Exception('Unable to read selected image.'));
    }
  });
  reader.readAsDataUrl(file);
  await readDone.future;

  final dataUrl = '${reader.result ?? ''}'.trim();
  if (dataUrl.isEmpty) {
    throw Exception('Unable to read selected image.');
  }

  final image = html.ImageElement(src: dataUrl);
  final imageReady = Completer<void>();
  image.onLoad.first.then((_) {
    if (!imageReady.isCompleted) imageReady.complete();
  });
  image.onError.first.then((_) {
    if (!imageReady.isCompleted) {
      imageReady.completeError(Exception('Unable to load selected image.'));
    }
  });
  await imageReady.future;

  try {
    final detector = html.BarcodeDetector();
    final results = await detector.detect(image);
    if (results.isEmpty) return null;
    for (final result in results) {
      if (result is html.DetectedBarcode) {
        final rawValue = (result.rawValue ?? '').trim();
        if (rawValue.isNotEmpty) return rawValue;
      }
    }
    return null;
  } catch (_) {
    throw UnsupportedError(
      'This browser does not support QR scan from image. Use camera scan instead.',
    );
  }
}
