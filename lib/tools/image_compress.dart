import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

const int chatImageMaxSide = 1600;
const int chatImageQuality = 80;
const int chatImageMaxBytes = 1024 * 1024;

Future<Uint8List> compressChatImage(Uint8List bytes) =>
    compute(shrinkChatImage, bytes);

bool _startsWith(Uint8List bytes, List<int> signature, [int offset = 0]) {
  if (bytes.length < offset + signature.length) return false;
  for (var i = 0; i < signature.length; i++) {
    if (bytes[offset + i] != signature[i]) return false;
  }
  return true;
}

img.Image? _decodeSupported(Uint8List bytes) {
  if (_startsWith(bytes, const [0xFF, 0xD8])) return img.decodeJpg(bytes);
  if (_startsWith(bytes, const [0x89, 0x50, 0x4E, 0x47])) {
    return img.decodePng(bytes);
  }
  if (_startsWith(bytes, const [0x57, 0x45, 0x42, 0x50], 8)) {
    return img.decodeWebP(bytes);
  }
  return null;
}

img.Image _decode(Uint8List bytes) {
  try {
    final decoded = _decodeSupported(bytes);
    if (decoded != null) return decoded;
  } on Object {
    throw const FormatException('This file is not a supported image.');
  }
  throw const FormatException('This file is not a supported image.');
}

Uint8List shrinkChatImage(Uint8List bytes) {
  final decoded = _decode(bytes);
  final upright = img.bakeOrientation(decoded);
  final longest = math.max(upright.width, upright.height);
  final resized = longest <= chatImageMaxSide
      ? upright
      : img.copyResize(
          upright,
          width: upright.width >= upright.height ? chatImageMaxSide : null,
          height: upright.height > upright.width ? chatImageMaxSide : null,
          interpolation: img.Interpolation.average,
        );
  resized.exif = img.ExifData();
  var quality = chatImageQuality;
  var encoded = img.encodeJpg(resized, quality: quality);
  while (encoded.length > chatImageMaxBytes && quality > 40) {
    quality -= 10;
    encoded = img.encodeJpg(resized, quality: quality);
  }
  return encoded;
}
