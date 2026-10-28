import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:preconnect/tools/jpeg_encoder.dart';
import 'package:preconnect/tools/pdf_pages.dart';
import 'package:preconnect/tools/print_compose.dart';

const int _maxPhotoWidth = 2480;
const int _photoQuality = 90;

final Uint8List _orientationProbe = base64Decode(
  '/9j/4AAQSkZJRgABAQAAAQABAAD/4QAiRXhpZgAATU0AKgAAAAgAAQESAAMAAAABAAYAAAAAAAD/'
  '2wBDAAMCAgMCAgMDAwMEAwMEBQgFBQQEBQoHBwYIDAoMDAsKCwsNDhIQDQ4RDgsLEBYQERMUFRUV'
  'DA8XGBYUGBIUFRT/2wBDAQMEBAUEBQkFBQkUDQsNFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQU'
  'FBQUFBQUFBQUFBQUFBQUFBQUFBQUFBT/wAARCAABAAIDASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEA'
  'AAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJx'
  'FDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNk'
  'ZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJ'
  'ytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQF'
  'BgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMz'
  'UvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3'
  'eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna'
  '4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwD4H8Q/8h/Uv+vmX/0M0UUV/ptkP/Ipwn/X'
  'uH/pKPAzr/kZ4r/r5P8A9KZ//9k=',
);

Future<bool>? _decoderOrients;

Future<bool> _decoderAppliesOrientation() => _decoderOrients ??= () async {
  try {
    final codec = await ui.instantiateImageCodec(_orientationProbe);
    final frame = await codec.getNextFrame();
    final turned = frame.image.width == 1 && frame.image.height == 2;
    frame.image.dispose();
    codec.dispose();
    return turned;
  } catch (_) {
    return false;
  }
}();

int exifOrientation(Uint8List bytes) {
  if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) return 1;
  var offset = 2;
  while (offset + 4 <= bytes.length) {
    if (bytes[offset] != 0xFF) return 1;
    final marker = bytes[offset + 1];
    if (marker == 0xDA || marker == 0xD9) return 1;
    final length = (bytes[offset + 2] << 8) | bytes[offset + 3];
    final start = offset + 4;
    if (marker == 0xE1 &&
        length >= 16 &&
        start + 6 <= bytes.length &&
        bytes[start] == 0x45 &&
        bytes[start + 1] == 0x78 &&
        bytes[start + 2] == 0x69 &&
        bytes[start + 3] == 0x66) {
      return _tiffOrientation(bytes, start + 6, offset + 2 + length);
    }
    offset += 2 + length;
  }
  return 1;
}

int _tiffOrientation(Uint8List bytes, int tiff, int end) {
  if (tiff + 8 > bytes.length || end > bytes.length) return 1;
  final little = bytes[tiff] == 0x49;
  int u16(int at) => little
      ? bytes[at] | (bytes[at + 1] << 8)
      : (bytes[at] << 8) | bytes[at + 1];
  int u32(int at) => little
      ? bytes[at] |
            (bytes[at + 1] << 8) |
            (bytes[at + 2] << 16) |
            (bytes[at + 3] << 24)
      : (bytes[at] << 24) |
            (bytes[at + 1] << 16) |
            (bytes[at + 2] << 8) |
            bytes[at + 3];
  final ifd = tiff + u32(tiff + 4);
  if (ifd + 2 > end) return 1;
  final count = u16(ifd);
  for (var i = 0; i < count; i++) {
    final entry = ifd + 2 + i * 12;
    if (entry + 12 > end) return 1;
    if (u16(entry) == 0x0112) {
      final value = u16(entry + 8);
      return value >= 1 && value <= 8 ? value : 1;
    }
  }
  return 1;
}

Float64List exifTransform(int orientation, double width, double height) {
  final (a, b, c, d, tx, ty) = switch (orientation) {
    2 => (-1.0, 0.0, 0.0, 1.0, width, 0.0),
    3 => (-1.0, 0.0, 0.0, -1.0, width, height),
    4 => (1.0, 0.0, 0.0, -1.0, 0.0, height),
    5 => (0.0, 1.0, 1.0, 0.0, 0.0, 0.0),
    6 => (0.0, 1.0, -1.0, 0.0, height, 0.0),
    7 => (0.0, -1.0, -1.0, 0.0, height, width),
    8 => (0.0, -1.0, 1.0, 0.0, 0.0, width),
    _ => (1.0, 0.0, 0.0, 1.0, 0.0, 0.0),
  };
  return Float64List.fromList([
    a,
    b,
    0,
    0,
    c,
    d,
    0,
    0,
    0,
    0,
    1,
    0,
    tx,
    ty,
    0,
    1,
  ]);
}

Future<Uint8List> printableImageJpeg(Uint8List bytes) async =>
    (await printablePhoto(bytes)).jpeg;

Future<JpegPage> printablePhoto(Uint8List bytes) async {
  const unreadable = PrintComposeException('This image could not be read');
  final ui.Image source;
  try {
    final codec = await ui.instantiateImageCodec(bytes);
    source = (await codec.getNextFrame()).image;
    codec.dispose();
  } catch (_) {
    throw unreadable;
  }
  try {
    final orientation = await _decoderAppliesOrientation()
        ? 1
        : exifOrientation(bytes);
    final swapped = orientation >= 5;
    final uprightWidth = (swapped ? source.height : source.width).toDouble();
    final uprightHeight = (swapped ? source.width : source.height).toDouble();
    final turn = uprightWidth > uprightHeight;
    final pageWidth = turn ? uprightHeight : uprightWidth;
    final pageHeight = turn ? uprightWidth : uprightHeight;
    final scale = pageWidth > _maxPhotoWidth ? _maxPhotoWidth / pageWidth : 1.0;
    final width = (pageWidth * scale).round();
    final height = (pageHeight * scale).round();

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      ui.Paint()..color = const ui.Color(0xFFFFFFFF),
    );
    canvas.scale(scale);
    if (turn) canvas.transform(exifTransform(6, uprightWidth, uprightHeight));
    if (orientation != 1) {
      canvas.transform(
        exifTransform(
          orientation,
          source.width.toDouble(),
          source.height.toDouble(),
        ),
      );
    }
    canvas.drawImage(
      source,
      ui.Offset.zero,
      ui.Paint()..filterQuality = ui.FilterQuality.high,
    );
    final picture = recorder.endRecording();
    final flat = await picture.toImage(width, height);
    final data = await flat.toByteData(format: ui.ImageByteFormat.rawRgba);
    flat.dispose();
    picture.dispose();
    final jpeg = await compute(
      encodeJpegPixels,
      JpegPixels(width, height, data!.buffer.asUint8List(), _photoQuality),
    );
    return JpegPage(jpeg, width, height, fill: false);
  } finally {
    source.dispose();
  }
}
