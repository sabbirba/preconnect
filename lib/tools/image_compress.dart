import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

const int chatImageMaxSide = 1280;
const int chatImageQuality = 75;
const int chatImageMaxBytes = 600 * 1024;

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

img.Image _fitWithin(img.Image image, int maxSide) {
  final longest = math.max(image.width, image.height);
  if (longest <= maxSide) return image;
  return img.copyResize(
    image,
    width: image.width >= image.height ? maxSide : null,
    height: image.height > image.width ? maxSide : null,
    interpolation: img.Interpolation.average,
  );
}

Uint8List shrinkChatImage(Uint8List bytes) {
  final upright = img.bakeOrientation(_decode(bytes));
  var side = chatImageMaxSide;
  var resized = _fitWithin(upright, side);
  resized.exif = img.ExifData();
  var quality = chatImageQuality;
  var encoded = img.encodeJpg(resized, quality: quality);
  while (encoded.length > chatImageMaxBytes) {
    if (quality > 45) {
      quality -= 10;
    } else {
      side = (side * 0.8).round();
      resized = _fitWithin(upright, side);
      resized.exif = img.ExifData();
    }
    encoded = img.encodeJpg(resized, quality: quality);
  }
  return encoded;
}
