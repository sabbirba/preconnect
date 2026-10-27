import 'dart:math' as math;

class PrintLayout {
  PrintLayout._();

  static const double a4Width = 595.2756;
  static const double a4Height = 841.8898;
  static const double printableMargin = 14.17;
  static const double cellInset = 4;
  static const double sizeTolerance = 3;

  static int pagesPerSheetOf(String value) {
    switch (value) {
      case '2-in-1':
        return 2;
      case '4-in-1':
        return 4;
      default:
        return 1;
    }
  }

  static double marginFor(String fittingMode) {
    return fittingMode == 'Fit on Printable Area' ? printableMargin : 0;
  }

  static List<int>? parsePageRange(String input, int total) {
    final text = input.trim();
    if (text.isEmpty) return List<int>.generate(total, (i) => i);
    final pages = <int>[];
    for (final part in text.split(',')) {
      final token = part.trim();
      if (token.isEmpty) return null;
      final bounds = token.split('-');
      if (bounds.length > 2) return null;
      final start = int.tryParse(bounds.first.trim());
      final end = bounds.length == 2 ? int.tryParse(bounds.last.trim()) : start;
      if (start == null || end == null || start < 1 || end < start) {
        return null;
      }
      for (var page = start; page <= end && page <= total; page++) {
        pages.add(page - 1);
      }
    }
    return pages;
  }

  static List<List<int?>> planSheets(
    int pageCount,
    int perSheet, {
    bool booklet = false,
  }) {
    if (pageCount <= 0) return const <List<int?>>[];
    if (booklet) {
      final padded = ((pageCount + 3) ~/ 4) * 4;
      int? at(int index) => index < pageCount ? index : null;
      return <List<int?>>[
        for (var leaf = 0; leaf < padded ~/ 4; leaf++) ...[
          <int?>[at(padded - 1 - 2 * leaf), at(2 * leaf)],
          <int?>[at(2 * leaf + 1), at(padded - 2 - 2 * leaf)],
        ],
      ];
    }
    return <List<int?>>[
      for (var start = 0; start < pageCount; start += perSheet)
        <int?>[
          for (var offset = 0; offset < perSheet; offset++)
            start + offset < pageCount ? start + offset : null,
        ],
    ];
  }

  static int sheetsNeeded(int sides, {required bool duplex}) {
    return duplex ? (sides + 1) ~/ 2 : sides;
  }

  static List<Cell> cellsFor(
    int perSheet, {
    required double margin,
    required bool booklet,
  }) {
    final width = a4Width - 2 * margin;
    final height = a4Height - 2 * margin;
    final inset = perSheet > 1 || booklet ? cellInset : 0.0;
    final columns = !booklet && perSheet == 4 ? 2 : 1;
    final rows = booklet ? 2 : perSheet ~/ columns;
    final cellWidth = width / columns;
    final cellHeight = height / rows;
    return <Cell>[
      for (var row = 0; row < rows; row++)
        for (var column = 0; column < columns; column++)
          Cell(
            margin + column * cellWidth + inset,
            margin + row * cellHeight + inset,
            cellWidth - 2 * inset,
            cellHeight - 2 * inset,
          ),
    ];
  }

  static Placement place(
    double sourceWidth,
    double sourceHeight,
    Cell cell, {
    bool? forceRotate,
  }) {
    final upright = math.min(
      cell.width / sourceWidth,
      cell.height / sourceHeight,
    );
    final turned = math.min(
      cell.width / sourceHeight,
      cell.height / sourceWidth,
    );
    final rotate = forceRotate ?? turned > upright * 1.05;
    return Placement(
      rotate: rotate,
      scale: rotate ? turned : upright,
      centerX: cell.left + cell.width / 2,
      centerY: cell.top + cell.height / 2,
    );
  }

  static bool isPortrait(double width, double height) {
    return height >= width - sizeTolerance;
  }

  static double sheetDpiFor(int sides) {
    if (sides > 120) return 150;
    if (sides > 40) return 170;
    return 200;
  }

  static int jpegQualityFor(int sides) => sides > 40 ? 75 : 85;

  static bool needsShortEdgeBinding(int perSheet, {required bool booklet}) {
    return booklet || perSheet == 2;
  }
}

class Cell {
  const Cell(this.left, this.top, this.width, this.height);

  final double left;
  final double top;
  final double width;
  final double height;
}

class Placement {
  const Placement({
    required this.rotate,
    required this.scale,
    required this.centerX,
    required this.centerY,
  });

  final bool rotate;
  final double scale;
  final double centerX;
  final double centerY;
}
