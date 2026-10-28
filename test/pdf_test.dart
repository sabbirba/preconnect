import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:preconnect/tools/jpeg_encoder.dart';
import 'package:preconnect/tools/pdf_pages.dart';

JpegPage _page(int width, int height, {bool fill = true}) {
  final pixels = Uint8List(width * height * 4)
    ..fillRange(0, width * height * 4, 255);
  return JpegPage(
    encodeJpeg(pixels, width, height, quality: 80),
    width,
    height,
    fill: fill,
  );
}

void main() {
  group('jpeg pages pdf', () {
    test('has one page object per picture and a valid cross reference', () {
      final pdf = jpegPagesPdf([_page(80, 113), _page(40, 20, fill: false)]);
      final text = latin1.decode(pdf);
      expect(text.startsWith('%PDF-1.4'), isTrue);
      expect(text.trimRight().endsWith('%%EOF'), isTrue);
      expect(RegExp(r'/Type /Page ').allMatches(text).length, 2);
      expect(text, contains('/Count 2'));

      final startxref = int.parse(
        RegExp(r'startxref\n(\d+)').firstMatch(text)!.group(1)!,
      );
      expect(text.substring(startxref, startxref + 4), 'xref');

      final entries = RegExp(r'(\d{10}) 00000 n ').allMatches(text).toList();
      expect(entries.length, 2 + 2 * 3);
      for (var i = 0; i < entries.length; i++) {
        final offset = int.parse(entries[i].group(1)!);
        expect(
          text.substring(offset).startsWith('${i + 1} 0 obj'),
          isTrue,
          reason: 'object ${i + 1}',
        );
      }
    });

    test('stream lengths match the embedded data', () {
      final page = _page(64, 64);
      final pdf = jpegPagesPdf([page]);
      final text = latin1.decode(pdf);
      expect(text, contains('/Length ${page.jpeg.length}'));
      expect(text, contains('/Filter /DCTDecode'));
      final start = text.indexOf('stream\n', text.indexOf('/DCTDecode')) + 7;
      expect(pdf.sublist(start, start + 2), [0xFF, 0xD8]);
      expect(
        pdf.sublist(start + page.jpeg.length - 2, start + page.jpeg.length),
        [0xFF, 0xD9],
      );
    });

    test('a photo is fitted and centered, a sheet fills the page', () {
      final fitted = latin1.decode(jpegPagesPdf([_page(100, 50, fill: false)]));
      final filled = latin1.decode(jpegPagesPdf([_page(100, 50)]));
      expect(fitted, contains('q 595.276 0 0 297.638 0.000 272.126 cm'));
      expect(filled, contains('q 595.276 0 0 841.890 0.000 0.000 cm'));
    });
  });
}
