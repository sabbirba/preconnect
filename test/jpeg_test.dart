import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:preconnect/tools/jpeg_encoder.dart';
import 'package:preconnect/tools/photo_print.dart';

Uint8List _gradient(int width, int height) {
  final pixels = Uint8List(width * height * 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final i = (y * width + x) * 4;
      pixels[i] = width == 1 ? 0 : x * 255 ~/ (width - 1);
      pixels[i + 1] = height == 1 ? 0 : y * 255 ~/ (height - 1);
      pixels[i + 2] = ((x ~/ 8 + y ~/ 8) % 2 == 0) ? 40 : 220;
      pixels[i + 3] = 255;
    }
  }
  return pixels;
}

Uint8List _png(int width, int height, img.Color Function(int x, int y) paint) {
  final image = img.Image(width: width, height: height, numChannels: 3);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      image.setPixel(x, y, paint(x, y));
    }
  }
  return Uint8List.fromList(img.encodePng(image));
}

img.Color _redCorner(int x, int y) =>
    x < 40 && y < 40 ? img.ColorRgb8(255, 0, 0) : img.ColorRgb8(255, 255, 255);

bool _isRed(img.Pixel pixel) => pixel.r > 200 && pixel.g < 90 && pixel.b < 90;

void main() {
  group('jpeg encoder', () {
    for (final size in [
      (64, 48),
      (13, 7),
      (1, 1),
      (8, 8),
      (17, 33),
      (200, 150),
    ]) {
      test('${size.$1}x${size.$2} decodes back close to the source', () {
        final (width, height) = size;
        final source = _gradient(width, height);
        final decoded = img.decodeJpg(
          encodeJpeg(source, width, height, quality: 90),
        )!;
        expect(decoded.width, width);
        expect(decoded.height, height);
        var total = 0;
        for (var y = 0; y < height; y++) {
          for (var x = 0; x < width; x++) {
            final pixel = decoded.getPixel(x, y);
            final i = (y * width + x) * 4;
            total +=
                (pixel.r - source[i]).abs().toInt() +
                (pixel.g - source[i + 1]).abs().toInt() +
                (pixel.b - source[i + 2]).abs().toInt();
          }
        }
        expect(total / (width * height * 3), lessThan(6));
      });
    }

    test('lower quality gives a smaller file', () {
      final source = _gradient(200, 150);
      final low = encodeJpeg(source, 200, 150, quality: 40).length;
      final high = encodeJpeg(source, 200, 150, quality: 95).length;
      expect(low, lessThan(high));
    });

    test('white pages stay white', () {
      final white = Uint8List(100 * 100 * 4)..fillRange(0, 100 * 100 * 4, 255);
      final pixel = img
          .decodeJpg(encodeJpeg(white, 100, 100, quality: 85))!
          .getPixel(50, 50);
      expect(pixel.r, greaterThan(250));
      expect(pixel.g, greaterThan(250));
      expect(pixel.b, greaterThan(250));
    });
  });

  group('exif orientation', () {
    Uint8List jpegWith(int? orientation) {
      final image = img.Image(width: 30, height: 20, numChannels: 3);
      if (orientation != null) {
        image.exif.imageIfd.orientation = orientation;
      }
      return Uint8List.fromList(img.encodeJpg(image));
    }

    test('is read from a JPEG', () {
      for (final orientation in [3, 6, 8]) {
        expect(exifOrientation(jpegWith(orientation)), orientation);
      }
    });

    test('defaults to upright without exif or for other data', () {
      expect(exifOrientation(jpegWith(null)), 1);
      expect(exifOrientation(Uint8List.fromList([1, 2, 3, 4, 5])), 1);
      expect(exifOrientation(Uint8List(0)), 1);
    });

    test('transform sends raw corners to the upright corners', () {
      (double, double) apply(Float64List m, double x, double y) =>
          (m[0] * x + m[4] * y + m[12], m[1] * x + m[5] * y + m[13]);
      const width = 4.0, height = 2.0;
      final expected = <int, (double, double)>{
        1: (0, 0),
        2: (width, 0),
        3: (width, height),
        4: (0, height),
        5: (0, 0),
        6: (height, 0),
        7: (height, width),
        8: (0, width),
      };
      expected.forEach((orientation, corner) {
        final result = apply(exifTransform(orientation, width, height), 0, 0);
        expect(result, corner, reason: 'orientation $orientation');
      });
    });
  });

  group('photo printing', () {
    Future<img.Image> print(Uint8List bytes) async =>
        img.decodeJpg(await printableImageJpeg(bytes))!;

    test(
      'landscape photo turns clockwise so its top left goes top right',
      () async {
        final result = await print(_png(400, 300, _redCorner));
        expect(result.width, 300);
        expect(result.height, 400);
        expect(_isRed(result.getPixel(result.width - 10, 10)), isTrue);
        expect(_isRed(result.getPixel(10, 10)), isFalse);
      },
    );

    test('portrait photo keeps its orientation', () async {
      final result = await print(_png(300, 400, _redCorner));
      expect((result.width, result.height), (300, 400));
      expect(_isRed(result.getPixel(10, 10)), isTrue);
    });

    test('a photo tagged upside down is printed upright', () async {
      final image = img.Image(width: 300, height: 400, numChannels: 3);
      for (var y = 0; y < 400; y++) {
        for (var x = 0; x < 300; x++) {
          image.setPixel(x, y, _redCorner(x, y));
        }
      }
      image.exif.imageIfd.orientation = 3;
      final jpeg = Uint8List.fromList(img.encodeJpg(image, quality: 95));
      final result = await print(jpeg);
      expect((result.width, result.height), (300, 400));
      expect(_isRed(result.getPixel(289, 389)), isTrue);
      expect(_isRed(result.getPixel(10, 10)), isFalse);
    });

    test('wide photos are limited to the print width', () async {
      final result = await print(
        _png(3000, 4000, (x, y) => img.ColorRgb8(0, 0, 255)),
      );
      expect(result.width, 2480);
      expect(result.height, 3307);
    });
  });
}
