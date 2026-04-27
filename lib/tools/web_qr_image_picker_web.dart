@JS()
library;

// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:js_interop';

import 'package:file_picker/file_picker.dart';
import 'package:web/web.dart' as web;

extension type BarcodeDetector._(JSObject _) implements JSObject {
  external factory BarcodeDetector(BarcodeDetectorInit init);

  external JSPromise<JSArray<DetectedBarcode>> detect(
    web.HTMLImageElement image,
  );
}

extension type BarcodeDetectorInit._(JSObject _) implements JSObject {
  external factory BarcodeDetectorInit({required JSArray<JSString> formats});
}

extension type DetectedBarcode._(JSObject _) implements JSObject {
  external String get rawValue;
}

Future<String?> pickQrFromSystemImage() async {
  final picked = await FilePicker.pickFiles(
    type: FileType.image,
    allowMultiple: false,
    withData: true,
  );
  if (picked == null || picked.files.isEmpty) return null;

  final file = picked.files.first;
  final bytes = file.bytes;
  if (bytes == null || bytes.isEmpty) {
    throw UnsupportedError('Selected image could not be read.');
  }

  final detector = BarcodeDetector(
    BarcodeDetectorInit(formats: ['qr_code'.toJS].toJS),
  );

  final image = web.HTMLImageElement();
  final blob = web.Blob([bytes.toJS].toJS);
  final objectUrl = web.URL.createObjectURL(blob);
  try {
    image.src = objectUrl;
    await image.decode().toDart;

    final detections = (await detector.detect(image).toDart).toDart;
    if (detections.isEmpty) return null;

    final value = detections.first.rawValue.trim();
    return value.isEmpty ? null : value;
  } finally {
    web.URL.revokeObjectURL(objectUrl);
  }
}
