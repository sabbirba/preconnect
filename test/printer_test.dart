import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:preconnect/pages/wifi_printer.dart';
import 'package:preconnect/tools/http/http_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'local blank PDF page contains valid A4 dimensions and top corner dot',
    () {
      final pdfBytes = CampusPrinterPage.createLocalBlankPdfForTesting();
      final pdfText = utf8.decode(pdfBytes);

      expect(pdfText, contains('%PDF-1.4'));
      expect(pdfText, contains('/MediaBox [0 0 595 842]'));
      expect(pdfText, contains('590 835 1 1 re f'));
      expect(pdfText, contains('%%EOF'));
    },
  );

  test('pjlPrefix includes standard PJL configuration directives', () {
    final prefix = HttpUtils.pjlPrefix(
      jobName: 'Test Job',
      copies: 1,
      duplexMode: 'OFF',
      collateMode: 'OFF',
      isPostScript: false,
      pagesPerSheet: '1-in-1',
      fittingMode: 'Default',
      staple: 'OFF',
      punch: 'OFF',
      jobOffset: 'OFF',
      slipSheet: 'OFF',
      booklet: 'OFF',
    );

    expect(prefix, contains('@PJL JOB NAME = "Test Job"\r\n'));
    expect(prefix, contains('@PJL SET COPIES = 1\r\n'));

    final fitOnPaperPrefix = HttpUtils.pjlPrefix(
      jobName: 'Test Job',
      copies: 1,
      duplexMode: 'OFF',
      collateMode: 'OFF',
      isPostScript: false,
      pagesPerSheet: '1-in-1',
      fittingMode: 'Fit on Paper',
      staple: 'OFF',
      punch: 'OFF',
      jobOffset: 'OFF',
      slipSheet: 'OFF',
      booklet: 'OFF',
    );
    expect(fitOnPaperPrefix, contains('@PJL SET FITTOPAGESIZE = ON\r\n'));
    expect(fitOnPaperPrefix, contains('@PJL SET ZOOM = FIT\r\n'));

    final fitPrintablePrefix = HttpUtils.pjlPrefix(
      jobName: 'Test Job',
      copies: 1,
      duplexMode: 'OFF',
      collateMode: 'OFF',
      isPostScript: false,
      pagesPerSheet: '1-in-1',
      fittingMode: 'Fit on Printable Area',
      staple: 'OFF',
      punch: 'OFF',
      jobOffset: 'OFF',
      slipSheet: 'OFF',
      booklet: 'OFF',
    );
    expect(fitPrintablePrefix, contains('@PJL SET FITOPRINTABLE = ON\r\n'));
    expect(fitPrintablePrefix, contains('@PJL SET ZOOM = FIT\r\n'));

    final edgeToEdgePrefix = HttpUtils.pjlPrefix(
      jobName: 'Test Job',
      copies: 1,
      duplexMode: 'OFF',
      collateMode: 'OFF',
      isPostScript: false,
      pagesPerSheet: '1-in-1',
      fittingMode: 'Edge-to-Edge',
      staple: 'OFF',
      punch: 'OFF',
      jobOffset: 'OFF',
      slipSheet: 'OFF',
      booklet: 'OFF',
    );
    expect(edgeToEdgePrefix, contains('@PJL SET EDGETOEDGE = ON\r\n'));
  });

  test('lprControlFile formats control file with secure queue default', () {
    final control = HttpUtils.lprControlFile(
      client: '192.168.1.10',
      owner: 'student',
      printableJobName: 'test.pdf',
      dataCommand: 'f',
      dataFileName: 'dfA001192.168.1.10',
      safeFileName: 'test.pdf',
      copies: 1,
    );

    expect(control, contains('H192.168.1.10'));
    expect(control, contains('Pstudent'));
    expect(control, contains('Jtest.pdf'));
    expect(control, contains('fdfA001192.168.1.10'));
  });

  test(
    'wrapJpegInPdfForTesting generates valid A4 PDF with DCTDecode image filter',
    () {
      final fakeJpeg = Uint8List.fromList([
        0xFF,
        0xD8,
        0xFF,
        0xE0,
        0x00,
        0x10,
        0x4A,
        0x46,
        0x49,
        0x46,
        0x00,
        0xFF,
        0xD9,
      ]);
      final pdfBytes = CampusPrinterPage.wrapJpegInPdfForTesting(fakeJpeg);
      final pdfText = latin1.decode(pdfBytes, allowInvalid: true);

      expect(pdfText, contains('%PDF-1.4'));
      expect(pdfText, contains('/MediaBox [0 0 595 842]'));
      expect(pdfText, contains('/Count 1'));
      expect(pdfText, contains('/Filter /DCTDecode'));
      expect(pdfText, contains('%%EOF'));
    },
  );
}
