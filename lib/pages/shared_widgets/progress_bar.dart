import 'package:flutter/material.dart';

class SimpleProgressBar extends StatelessWidget {
  const SimpleProgressBar({
    super.key,
    required this.value,
    required this.color,
    this.height = 8,
    this.backgroundAlpha = 0.12,
  });

  final double value;
  final Color color;
  final double height;
  final double backgroundAlpha;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: LinearProgressIndicator(
        value: value,
        minHeight: height,
        backgroundColor: color.withValues(alpha: backgroundAlpha),
        valueColor: AlwaysStoppedAnimation<Color>(color),
      ),
    );
  }
}
