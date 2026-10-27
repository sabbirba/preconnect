import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:preconnect/tools/app_log.dart';
import 'package:preconnect/tools/print_layout.dart';
import 'package:printing/printing.dart';

class PrintComposeOptions {
  const PrintComposeOptions({
    required this.pagesPerSheet,
    required this.fittingMode,
    required this.booklet,
    required this.pageRange,
  });

  final String pagesPerSheet;
  final String fittingMode;
  final bool booklet;
  final String pageRange;
}

class ComposedPrint {
  const ComposedPrint({required this.bytes, required this.sheetSides});

  final Uint8List bytes;
  final int sheetSides;
}

class PrintComposeException implements Exception {
  const PrintComposeException(this.message);

  final String message;

  @override
  String toString() => message;
}

class PrintComposer {
  PrintComposer._();

  static const double _scanDpi = 36;
  static const int _blankLuma = 245;
  static const double _blankInkRatio = 0.0001;
  static const double _previewDpi = 110;

  static Future<ComposedPrint?> compose(
    Uint8List pdf,
    PrintComposeOptions options, {
    ValueChanged<double>? onProgress,
  }) async {
    if (kIsWeb) return null;
    try {
      return await _compose(pdf, options, onProgress);
    } on PrintComposeException {
      rethrow;
    } catch (error) {
      unawaited(AppLog.write('Print layout failed: $error'));
      throw const PrintComposeException('This PDF could not be read');
    }
  }

  static Future<int?> pageCount(Uint8List pdf) async {
    if (kIsWeb) return null;
    try {
      if (!(await Printing.info()).canRaster) return null;
      var count = 0;
      await for (final _ in Printing.raster(pdf, dpi: 4)) {
        count++;
      }
      return count > 0 ? count : null;
    } catch (error) {
      unawaited(AppLog.write('Page count failed: $error'));
      return null;
    }
  }

  static Future<Uint8List> imagePdf(Uint8List image) async {
    try {
      final jpeg = await compute(printableImageJpeg, image);
      final document = pw.Document();
      final provider = pw.MemoryImage(jpeg);
      document.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.zero,
          build: (_) =>
              pw.Center(child: pw.Image(provider, fit: pw.BoxFit.contain)),
        ),
      );
      return await document.save();
    } on PrintComposeException {
      rethrow;
    } catch (error) {
      unawaited(AppLog.write('Print image failed: $error'));
      throw const PrintComposeException('This image could not be read');
    }
  }

  static Future<ComposedPrint?> _compose(
    Uint8List pdf,
    PrintComposeOptions options,
    ValueChanged<double>? onProgress,
  ) async {
    final info = await Printing.info();
    if (!info.canRaster) return null;

    final pages = await _scan(pdf);
    if (pages.isEmpty) {
      throw const PrintComposeException(
        'This PDF could not be read. It may be password protected',
      );
    }

    final perSheet = PrintLayout.pagesPerSheetOf(options.pagesPerSheet);
    final ranged = PrintLayout.parsePageRange(options.pageRange, pages.length);
    if (ranged == null) {
      throw const PrintComposeException('Page range is not valid');
    }
    final selected = <int>[
      for (final index in ranged)
        if (!pages[index].blank) index,
    ];
    if (selected.isEmpty) {
      throw const PrintComposeException('No pages left to print');
    }

    final untouched =
        perSheet == 1 &&
        !options.booklet &&
        selected.length == pages.length &&
        pages.every((page) => PrintLayout.isPortrait(page.width, page.height));
    if (untouched) return null;

    final sides = PrintLayout.planSheets(
      selected.length,
      perSheet,
      booklet: options.booklet,
    );
    final cells = PrintLayout.cellsFor(
      perSheet,
      margin: PrintLayout.marginFor(options.fittingMode),
      booklet: options.booklet,
    );

    final sheetDpi = PrintLayout.sheetDpiFor(sides.length);
    final quality = PrintLayout.jpegQualityFor(sides.length);
    final jpegs = <Uint8List>[];
    for (var sideIndex = 0; sideIndex < sides.length; sideIndex++) {
      jpegs.add(
        await _renderSide(
          pdf,
          pages,
          selected,
          sides[sideIndex],
          cells,
          booklet: options.booklet,
          sheetDpi: sheetDpi,
          quality: quality,
        ),
      );
      onProgress?.call((sideIndex + 1) / sides.length);
    }
    return ComposedPrint(
      bytes: await _assemble(jpegs),
      sheetSides: jpegs.length,
    );
  }

  static Stream<Uint8List> previewPages(Uint8List pdf) async* {
    await for (final raster in Printing.raster(pdf, dpi: _previewDpi)) {
      yield await raster.toPng();
    }
  }

  static Future<List<_PageInfo>> _scan(Uint8List pdf) async {
    final pages = <_PageInfo>[];
    await for (final raster in Printing.raster(pdf, dpi: _scanDpi)) {
      pages.add(
        _PageInfo(
          width: raster.width * 72 / _scanDpi,
          height: raster.height * 72 / _scanDpi,
          blank: _isBlank(raster.pixels),
        ),
      );
    }
    return pages;
  }

  static bool _isBlank(Uint8List rgba) {
    final total = rgba.length ~/ 4;
    final allowed = (total * _blankInkRatio).ceil();
    var ink = 0;
    for (var i = 0; i < rgba.length; i += 4) {
      final luma =
          (rgba[i] * 299 + rgba[i + 1] * 587 + rgba[i + 2] * 114) ~/ 1000;
      if (rgba[i + 3] > 0 && luma < _blankLuma && ++ink > allowed) {
        return false;
      }
    }
    return true;
  }

  static Future<Uint8List> _renderSide(
    Uint8List pdf,
    List<_PageInfo> pages,
    List<int> selected,
    List<int?> side,
    List<Cell> cells, {
    required bool booklet,
    required double sheetDpi,
    required int quality,
  }) async {
    final placements = <int, Placement>{};
    var dpi = _scanDpi;
    for (var slot = 0; slot < side.length; slot++) {
      final slotPage = side[slot];
      if (slotPage == null) continue;
      final source = pages[selected[slotPage]];
      final placement = PrintLayout.place(
        source.width,
        source.height,
        cells[slot],
        forceRotate: booklet ? true : null,
      );
      placements[slot] = placement;
      dpi = math.max(dpi, placement.scale * sheetDpi);
    }

    final sourceIndexes = <int>[
      for (final slot in placements.keys) selected[side[slot]!],
    ];
    final slots = placements.keys.toList();

    final factor = sheetDpi / 72;
    final width = (PrintLayout.a4Width * factor).round();
    final height = (PrintLayout.a4Height * factor).round();
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      ui.Paint()..color = const ui.Color(0xFFFFFFFF),
    );

    if (sourceIndexes.isNotEmpty) {
      var position = 0;
      await for (final raster in Printing.raster(
        pdf,
        pages: sourceIndexes,
        dpi: dpi.clamp(_scanDpi, 300),
      )) {
        final placement = placements[slots[position]]!;
        final source = pages[sourceIndexes[position]];
        position++;
        final image = await raster.toImage();
        final drawWidth = source.width * placement.scale * factor;
        final drawHeight = source.height * placement.scale * factor;
        canvas.save();
        canvas.translate(
          placement.centerX * factor,
          placement.centerY * factor,
        );
        if (placement.rotate) canvas.rotate(math.pi / 2);
        canvas.drawImageRect(
          image,
          ui.Rect.fromLTWH(
            0,
            0,
            image.width.toDouble(),
            image.height.toDouble(),
          ),
          ui.Rect.fromLTWH(
            -drawWidth / 2,
            -drawHeight / 2,
            drawWidth,
            drawHeight,
          ),
          ui.Paint()
            ..filterQuality = ui.FilterQuality.high
            ..isAntiAlias = true,
        );
        canvas.restore();
        image.dispose();
      }
    }

    final picture = recorder.endRecording();
    final sheet = await picture.toImage(width, height);
    final data = await sheet.toByteData(format: ui.ImageByteFormat.rawRgba);
    sheet.dispose();
    picture.dispose();
    return compute(
      _encodeJpeg,
      _SheetPixels(width, height, data!.buffer.asUint8List(), quality),
    );
  }

  static Future<Uint8List> _assemble(List<Uint8List> jpegs) async {
    final document = pw.Document(compress: true);
    for (final jpeg in jpegs) {
      final image = pw.MemoryImage(jpeg);
      document.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.zero,
          build: (_) => pw.Image(image, fit: pw.BoxFit.fill),
        ),
      );
    }
    return document.save();
  }
}

class _PageInfo {
  const _PageInfo({
    required this.width,
    required this.height,
    required this.blank,
  });

  final double width;
  final double height;
  final bool blank;
}

class _SheetPixels {
  const _SheetPixels(this.width, this.height, this.rgba, this.quality);

  final int width;
  final int height;
  final Uint8List rgba;
  final int quality;
}

Uint8List _encodeJpeg(_SheetPixels sheet) {
  final rgb = Uint8List(sheet.width * sheet.height * 3);
  for (var i = 0, o = 0; i < sheet.rgba.length; i += 4, o += 3) {
    rgb[o] = sheet.rgba[i];
    rgb[o + 1] = sheet.rgba[i + 1];
    rgb[o + 2] = sheet.rgba[i + 2];
  }
  final image = img.Image.fromBytes(
    width: sheet.width,
    height: sheet.height,
    bytes: rgb.buffer,
    numChannels: 3,
  );
  return Uint8List.fromList(img.encodeJpg(image, quality: sheet.quality));
}

Uint8List printableImageJpeg(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw const PrintComposeException('This image could not be read');
  }
  var image = img.bakeOrientation(decoded);
  if (image.hasAlpha) {
    final flat = img.Image(
      width: image.width,
      height: image.height,
      numChannels: 3,
    )..clear(img.ColorRgb8(255, 255, 255));
    img.compositeImage(flat, image);
    image = flat;
  }
  if (image.width > image.height) {
    image = img.copyRotate(image, angle: 90);
  }
  if (image.width > 2480) {
    image = img.copyResize(image, width: 2480);
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: 90));
}
