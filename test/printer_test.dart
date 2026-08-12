import 'dart:convert';
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
      expect(pdfText, contains('/MediaBox [0 0 595.28 841.89]'));
      expect(pdfText, contains('590 835 1 1 re f'));
      expect(pdfText, contains('%%EOF'));
    },
  );

  test('pjlPrefix includes Toshiba e-STUDIO A4 paper size directives', () {
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

    expect(prefix, contains('@PJL SET PAPER = A4\r\n'));
    expect(prefix, contains('@PJL SET PAPERSIZE = A4\r\n'));
    expect(prefix, contains('@PJL SET MEDIASIZE = A4\r\n'));
    expect(prefix, contains('@PJL SET TOSHIBAPAPER = A4\r\n'));
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
}
