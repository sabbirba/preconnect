import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:preconnect/tools/print_compose.dart';
import 'package:preconnect/tools/http/http_utils.dart';
import 'package:preconnect/tools/print_layout.dart';

String _pjl({
  String pagesPerSheet = '1-in-1',
  String fittingMode = 'Fit on Paper',
  String duplexMode = 'OFF',
  String booklet = 'Off',
  bool layoutBaked = false,
}) {
  return HttpUtils.pjlPrefix(
    jobName: 'job',
    copies: 1,
    duplexMode: duplexMode,
    collateMode: 'OFF',
    isPostScript: false,
    pagesPerSheet: pagesPerSheet,
    fittingMode: fittingMode,
    staple: 'Off',
    punch: 'Off',
    jobOffset: 'Off',
    slipSheet: 'Off',
    booklet: booklet,
    layoutBaked: layoutBaked,
  );
}

void main() {
  group('parsePageRange', () {
    test('empty selects every page', () {
      expect(PrintLayout.parsePageRange('', 3), [0, 1, 2]);
    });

    test('ranges and singles are zero based and clipped to the total', () {
      expect(PrintLayout.parsePageRange('1-2, 5, 8-12', 9), [0, 1, 4, 7, 8]);
    });

    test('invalid input returns null', () {
      expect(PrintLayout.parsePageRange('a', 5), isNull);
      expect(PrintLayout.parsePageRange('3-1', 5), isNull);
      expect(PrintLayout.parsePageRange('1,,2', 5), isNull);
      expect(PrintLayout.parsePageRange('0-2', 5), isNull);
    });
  });

  group('planSheets', () {
    test('groups pages per sheet and pads the last sheet', () {
      expect(PrintLayout.planSheets(5, 4), [
        [0, 1, 2, 3],
        [4, null, null, null],
      ]);
    });

    test('booklet orders pages for folding', () {
      expect(PrintLayout.planSheets(8, 2, booklet: true), [
        [7, 0],
        [1, 6],
        [5, 2],
        [3, 4],
      ]);
    });

    test('booklet pads missing pages with blanks', () {
      expect(PrintLayout.planSheets(5, 2, booklet: true), [
        [null, 0],
        [1, null],
        [null, 2],
        [3, 4],
      ]);
    });

    test('sheet count halves for duplex', () {
      expect(PrintLayout.sheetsNeeded(5, duplex: true), 3);
      expect(PrintLayout.sheetsNeeded(5, duplex: false), 5);
    });
  });

  group('placement', () {
    test('landscape slide is rotated on a full A4 portrait sheet', () {
      final cells = PrintLayout.cellsFor(1, margin: 0, booklet: false);
      final placement = PrintLayout.place(960, 540, cells.single);
      expect(placement.rotate, isTrue);
      expect(placement.scale, closeTo(PrintLayout.a4Height / 960, 0.001));
    });

    test('portrait A4 page stays upright at full size', () {
      final cells = PrintLayout.cellsFor(1, margin: 0, booklet: false);
      final placement = PrintLayout.place(
        PrintLayout.a4Width,
        PrintLayout.a4Height,
        cells.single,
      );
      expect(placement.rotate, isFalse);
      expect(placement.scale, closeTo(1, 0.001));
    });

    test('landscape slides stay upright when stacked 2-in-1', () {
      final cells = PrintLayout.cellsFor(2, margin: 0, booklet: false);
      expect(cells, hasLength(2));
      expect(PrintLayout.place(960, 540, cells.first).rotate, isFalse);
    });

    test('portrait pages turn to fill stacked 2-in-1 cells', () {
      final cells = PrintLayout.cellsFor(2, margin: 0, booklet: false);
      expect(PrintLayout.place(595, 842, cells.first).rotate, isTrue);
    });

    test('4-in-1 uses a 2x2 grid inside the sheet', () {
      final cells = PrintLayout.cellsFor(4, margin: 0, booklet: false);
      expect(cells, hasLength(4));
      expect(cells[1].left, greaterThan(cells[0].left));
      expect(cells[2].top, greaterThan(cells[0].top));
      for (final cell in cells) {
        expect(cell.left + cell.width, lessThanOrEqualTo(PrintLayout.a4Width));
        expect(cell.top + cell.height, lessThanOrEqualTo(PrintLayout.a4Height));
      }
    });

    test('printable margin shrinks the cell', () {
      final full = PrintLayout.cellsFor(1, margin: 0, booklet: false).single;
      final inset = PrintLayout.cellsFor(
        1,
        margin: PrintLayout.marginFor('Fit on Printable Area'),
        booklet: false,
      ).single;
      expect(inset.width, lessThan(full.width));
    });
  });

  group('pass through and sizing', () {
    test('portrait pages of any size stay vector for the printer to fit', () {
      expect(PrintLayout.isPortrait(595, 842), isTrue);
      expect(PrintLayout.isPortrait(612, 792), isTrue);
      expect(PrintLayout.isPortrait(420, 595), isTrue);
      expect(PrintLayout.isPortrait(100, 100), isTrue);
    });

    test('landscape pages need the app to turn them', () {
      expect(PrintLayout.isPortrait(842, 595), isFalse);
      expect(PrintLayout.isPortrait(960, 540), isFalse);
    });

    test('large jobs use smaller sheets', () {
      expect(PrintLayout.sheetDpiFor(10), 200);
      expect(PrintLayout.sheetDpiFor(41), 170);
      expect(PrintLayout.sheetDpiFor(150), 150);
      expect(PrintLayout.jpegQualityFor(40), 85);
      expect(PrintLayout.jpegQualityFor(41), 75);
    });
  });

  group('image printing', () {
    Uint8List png(int width, int height, {bool alpha = false}) {
      final image = img.Image(
        width: width,
        height: height,
        numChannels: alpha ? 4 : 3,
      );
      img.fill(
        image,
        color: alpha ? img.ColorRgba8(255, 0, 0, 0) : img.ColorRgb8(0, 0, 255),
      );
      return Uint8List.fromList(img.encodePng(image));
    }

    test('landscape photo is turned upright and flattened to RGB', () {
      final jpeg = printableImageJpeg(png(400, 300));
      final decoded = img.decodeJpg(jpeg)!;
      expect(decoded.height, greaterThan(decoded.width));
    });

    test('transparent pixels turn white instead of black', () {
      final decoded = img.decodeJpg(
        printableImageJpeg(png(200, 300, alpha: true)),
      )!;
      final pixel = decoded.getPixel(100, 150);
      expect(pixel.r, greaterThan(240));
      expect(pixel.g, greaterThan(240));
      expect(pixel.b, greaterThan(240));
    });

    test('unreadable image fails with a print error', () {
      expect(
        () => printableImageJpeg(Uint8List.fromList(utf8.encode('nope'))),
        throwsA(isA<PrintComposeException>()),
      );
    });

    test('image becomes a one page PDF', () async {
      final pdf = await PrintComposer.imagePdf(png(300, 400));
      final text = latin1.decode(pdf, allowInvalid: true);
      expect(text.startsWith('%PDF'), isTrue);
      expect(RegExp(r'/Type\s*/Page\b').allMatches(text).length, 1);
    });
  });

  group('pjlPrefix', () {
    test('printer layout keeps NUP request when the app did not compose', () {
      final text = _pjl(pagesPerSheet: '4-in-1');
      expect(text, contains('@PJL SET NUP = 4'));
      expect(text, contains('@PJL SET ZOOM = FIT'));
    });

    test('composed layout turns printer NUP and scaling off', () {
      final text = _pjl(pagesPerSheet: '4-in-1', layoutBaked: true);
      expect(text, contains('@PJL SET NUP = OFF'));
      expect(text, contains('@PJL SET MULTIPAGE = OFF'));
      expect(text, isNot(contains('ZOOM = FIT')));
      expect(text, isNot(contains('FITTOPAGESIZE = ON')));
    });

    test(
      'composed booklet forces short edge duplex without printer booklet',
      () {
        final text = _pjl(booklet: 'On', layoutBaked: true);
        expect(text, contains('@PJL SET DUPLEX = ON'));
        expect(text, contains('@PJL SET BINDING = SHORTEDGE'));
        expect(text, isNot(contains('MULTIPAGE = BOOKLET')));
      },
    );

    test('composed 4-in-1 duplex binds on the long edge', () {
      final text = _pjl(
        pagesPerSheet: '4-in-1',
        duplexMode: 'ON',
        layoutBaked: true,
      );
      expect(text, contains('@PJL SET BINDING = LONGEDGE'));
    });
  });
}
