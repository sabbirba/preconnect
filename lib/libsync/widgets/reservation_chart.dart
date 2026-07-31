part of '../libsync_page.dart';

class _ChartPainter extends CustomPainter {
  _ChartPainter({
    required this.chartData,
    required this.selectedIndex,
    required this.isDark,
  });

  final List<_MonthChartData> chartData;
  final int? selectedIndex;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final axisPaint = Paint()
      ..color = isDark ? Colors.white30 : Colors.black87
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    final barPaint = Paint()
      ..color = const Color(0xFFF05A28)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final highlightPaint = Paint()
      ..color = const Color(0xFFF05A28)
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    const sideMargin = 16.0;
    const bottomMargin = 20.0;
    final chartWidth = size.width - 2 * sideMargin;
    final chartHeight = size.height - bottomMargin - 15;
    final maxVal = chartData.isEmpty
        ? 0.0
        : chartData
              .map((item) => item.count.toDouble())
              .reduce((a, b) => a > b ? a : b);

    canvas.drawLine(
      const Offset(sideMargin, 10),
      Offset(sideMargin, size.height - bottomMargin),
      axisPaint,
    );
    canvas.drawLine(
      Offset(sideMargin, size.height - bottomMargin),
      Offset(size.width - sideMargin, size.height - bottomMargin),
      axisPaint,
    );
    for (final tick in const [0.0, 1.0]) {
      final y = size.height - bottomMargin - tick * chartHeight;
      canvas.drawLine(
        Offset(sideMargin - 4, y),
        Offset(sideMargin, y),
        axisPaint,
      );
      final painter = _labelPainter(
        tick == 0 ? '0' : (maxVal > 0 ? maxVal.toInt().toString() : '1'),
        fontSize: 9,
      )..layout();
      painter.paint(
        canvas,
        Offset(sideMargin - painter.width - 4, y - painter.height / 2),
      );
    }
    if (chartData.isEmpty) return;

    final stepX = chartData.length > 1
        ? chartWidth / (chartData.length - 1)
        : chartWidth;
    for (var index = 0; index < chartData.length; index++) {
      final x = chartData.length > 1
          ? sideMargin + index * stepX
          : sideMargin + chartWidth / 2;
      final y = size.height - bottomMargin;
      canvas.drawLine(Offset(x, y), Offset(x, y + 4), axisPaint);
      final label = _labelPainter(
        chartData[index].name,
        fontSize: 8.5,
        bold: true,
      )..layout();
      label.paint(canvas, Offset(x - label.width / 2, y + 6));
      final value = maxVal == 0 ? 0.0 : chartData[index].count / maxVal;
      if (value > 0) {
        canvas.drawLine(
          Offset(x, y),
          Offset(x, y - value * chartHeight),
          selectedIndex == index ? highlightPaint : barPaint,
        );
      }
    }
    _paintTooltip(canvas, size, stepX, chartHeight, maxVal);
  }

  TextPainter _labelPainter(
    String text, {
    required double fontSize,
    bool bold = false,
  }) {
    return TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: isDark ? Colors.white70 : Colors.black87,
          fontSize: fontSize,
          fontWeight: bold ? FontWeight.w500 : null,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
  }

  void _paintTooltip(
    Canvas canvas,
    Size size,
    double stepX,
    double chartHeight,
    double maxVal,
  ) {
    final index = selectedIndex;
    if (index == null || index < 0 || index >= chartData.length) return;
    const sideMargin = 16.0;
    const bottomMargin = 20.0;
    final x = chartData.length > 1
        ? sideMargin + index * stepX
        : size.width / 2;
    final value = maxVal == 0 ? 0.0 : chartData[index].count / maxVal;
    final barY = size.height - bottomMargin - value * chartHeight;
    final painter = TextPainter(
      text: TextSpan(
        text: '${chartData[index].name}: ${chartData[index].count}',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final width = painter.width + 12;
    final height = painter.height + 8;
    final left = (x - width / 2).clamp(sideMargin, size.width - width);
    final top = (barY - height - 6).clamp(4.0, size.height);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(left, top, width, height),
        const Radius.circular(6),
      ),
      Paint()..color = const Color(0xFFF05A28),
    );
    painter.paint(canvas, Offset(left + 6, top + 4));
  }

  @override
  bool shouldRepaint(covariant _ChartPainter oldDelegate) {
    return oldDelegate.chartData != chartData ||
        oldDelegate.selectedIndex != selectedIndex ||
        oldDelegate.isDark != isDark;
  }
}

class _MonthChartData {
  _MonthChartData({
    required this.name,
    required this.count,
    required this.chronologicalIndex,
  });

  final String name;
  final int count;
  final int chronologicalIndex;
}
