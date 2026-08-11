import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:preconnect/tools/image_wrapper.dart';

void main() {
  group('ImageWrapper', () {
    test('identifies JPEG and PNG images correctly', () {
      final jpegBytes = Uint8List.fromList([
        0xFF,
        0xD8,
        0xFF,
        0xE0,
        0x00,
        0x10,
      ]);
      final pngBytes = Uint8List.fromList([
        0x89,
        0x50,
        0x4E,
        0x47,
        0x0D,
        0x0A,
        0x1A,
        0x0A,
        0x00,
        0x00,
        0x00,
        0x0D,
        0x49,
        0x48,
        0x44,
        0x52,
        0x00,
        0x00,
        0x00,
        0x10,
        0x00,
        0x00,
        0x00,
        0x10,
        0x08,
        0x02,
        0x00,
        0x00,
        0x00,
      ]);
      final pdfBytes = Uint8List.fromList([
        0x25,
        0x50,
        0x44,
        0x46,
        0x2D,
        0x31,
        0x2E,
        0x34,
      ]);

      expect(ImageWrapper.isImageFile('photo.jpg', jpegBytes), isTrue);
      expect(ImageWrapper.isImageFile('graphic.png', pngBytes), isTrue);
      expect(ImageWrapper.isImageFile('doc.pdf', pdfBytes), isFalse);
    });

    test('wraps JPEG into valid PDF 1.4 byte stream', () {
      final fakeJpeg = Uint8List.fromList([
        0xFF,
        0xD8,
        0xFF,
        0xC0,
        0x00,
        0x11,
        0x08,
        0x01,
        0x00,
        0x01,
        0x00,
        0x03,
        0x01,
        0x22,
        0x00,
        0x02,
        0x11,
        0x01,
        0x03,
        0x11,
        0x01,
        0xFF,
        0xD9,
      ]);

      final pdfBytes = ImageWrapper.wrapImageToPdf(
        bytes: fakeJpeg,
        fileName: 'test.jpg',
      );

      final pdfString = String.fromCharCodes(pdfBytes);
      expect(pdfString, startsWith('%PDF-1.4'));
      expect(pdfString, contains('/Type /Catalog'));
      expect(pdfString, contains('/Type /Pages'));
      expect(pdfString, contains('/Filter /DCTDecode'));
      expect(pdfString, contains('%%EOF'));
    });

    test('wraps PNG into valid PDF 1.4 byte stream', () {
      final idatRaw = zlib.encode([0, 255, 0, 0, 0, 255, 0, 0]);
      final pngHeader = [
        0x89,
        0x50,
        0x4E,
        0x47,
        0x0D,
        0x0A,
        0x1A,
        0x0A,
        0x00,
        0x00,
        0x00,
        0x0D,
        0x49,
        0x48,
        0x44,
        0x52,
        0x00,
        0x00,
        0x00,
        0x01,
        0x00,
        0x00,
        0x00,
        0x01,
        0x08,
        0x02,
        0x00,
        0x00,
        0x00,
      ];
      final idatLen = idatRaw.length;
      final pngBytes = Uint8List.fromList([
        ...pngHeader,
        (idatLen >> 24) & 0xFF,
        (idatLen >> 16) & 0xFF,
        (idatLen >> 8) & 0xFF,
        idatLen & 0xFF,
        0x49,
        0x44,
        0x41,
        0x54,
        ...idatRaw,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x49,
        0x45,
        0x4E,
        0x44,
        0xAE,
        0x42,
        0x60,
        0x82,
      ]);

      final pdfBytes = ImageWrapper.wrapImageToPdf(
        bytes: pngBytes,
        fileName: 'sample.png',
      );

      final pdfString = String.fromCharCodes(pdfBytes);
      expect(pdfString, startsWith('%PDF-1.4'));
      expect(pdfString, contains('/Type /Catalog'));
      expect(pdfString, contains('/Filter /FlateDecode'));
      expect(pdfString, contains('%%EOF'));
    });

    test(
      'correctly counts single and multi-page PDF pages across PDF structures',
      () {
        const singlePagePdf = '''
%PDF-1.4
1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj
2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 >> endobj
3 0 obj << /Type /Page /Parent 2 0 R >> endobj
xref
0 4
0000000000 65535 f 
0000000009 00000 n 
0000000058 00000 n 
0000000115 00000 n 
trailer << /Size 4 /Root 1 0 R >>
startxref
170
%%EOF
''';

        const multiPagePdf5 = '''
%PDF-1.4
1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj
2 0 obj << /Type /Pages /Kids [3 0 R 4 0 R 5 0 R 6 0 R 7 0 R] /Count 5 >> endobj
3 0 obj << /Type /Page /Parent 2 0 R >> endobj
4 0 obj << /Type /Page /Parent 2 0 R >> endobj
5 0 obj << /Type /Page /Parent 2 0 R >> endobj
6 0 obj << /Type /Page /Parent 2 0 R >> endobj
7 0 obj << /Type /Page /Parent 2 0 R >> endobj
xref
trailer << /Size 8 /Root 1 0 R >>
startxref
350
%%EOF
''';

        const hundredPagePdf = '''
%PDF-1.7
10 0 obj << /Type /Catalog /Pages 20 0 R >> endobj
20 0 obj << /Type /Pages /Count 128 >> endobj
''';

        final compressedObjStreamBytes = zlib.encode(
          '''
100 0 obj << /Type /Catalog /Pages 200 0 R >> endobj
200 0 obj << /Type /Pages /Count 45 >> endobj
'''
              .codeUnits,
        );

        final pdfWithCompressedObjStm = BytesBuilder(copy: false)
          ..add('%PDF-1.5\n'.codeUnits)
          ..add('3 0 obj\nstream\n'.codeUnits)
          ..add(compressedObjStreamBytes)
          ..add('\nendstream\nendobj\n%%EOF\n'.codeUnits);

        expect(
          ImageWrapper.readPdfPageCount(
            Uint8List.fromList(singlePagePdf.codeUnits),
          ),
          equals(1),
        );
        expect(
          ImageWrapper.readPdfPageCount(
            Uint8List.fromList(multiPagePdf5.codeUnits),
          ),
          equals(5),
        );
        expect(
          ImageWrapper.readPdfPageCount(
            Uint8List.fromList(hundredPagePdf.codeUnits),
          ),
          equals(128),
        );
        expect(
          ImageWrapper.readPdfPageCount(pdfWithCompressedObjStm.takeBytes()),
          equals(45),
        );
      },
    );
  });
}
