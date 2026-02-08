import 'package:qr/qr.dart';
import 'package:flutter/material.dart';

class QrPainter extends CustomPainter {
  final String data;
  final Color fgColor;
  final Color bgColor;

  QrPainter(
    this.data, {
    this.fgColor = Colors.black,
    this.bgColor = Colors.white,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final qrCode = QrCode.fromData(
      data: data,
      errorCorrectLevel: QrErrorCorrectLevel.L,
    );

    final qrImage = QrImage(qrCode);

    final bgPaint = Paint()..color = bgColor;
    canvas.drawRect(Offset.zero & size, bgPaint);

    final paint = Paint()..color = fgColor;
    final moduleSize = size.width / qrImage.moduleCount;

    for (var x = 0; x < qrImage.moduleCount; x++) {
      for (var y = 0; y < qrImage.moduleCount; y++) {
        if (qrImage.isDark(y, x)) {
          final rect = Rect.fromLTWH(
            x * moduleSize,
            y * moduleSize,
            moduleSize,
            moduleSize,
          );
          canvas.drawRect(rect, paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}
