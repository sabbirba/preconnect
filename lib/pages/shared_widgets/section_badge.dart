import 'package:flutter/material.dart';

class SectionBadge extends StatelessWidget {
  const SectionBadge({
    super.key,
    required this.label,
    required this.color,
    this.size = 40,
    this.fontSize = 14,
    this.fontWeight = FontWeight.w700,
    this.backgroundAlpha = 0.12,
    this.borderRadius = 12,
  });

  final String label;
  final Color color;
  final double size;
  final double fontSize;
  final FontWeight fontWeight;
  final double backgroundAlpha;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: backgroundAlpha),
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: fontWeight,
        ),
      ),
    );
  }
}
