import 'package:flutter/material.dart';

class LeadingIconBadge extends StatelessWidget {
  const LeadingIconBadge({
    super.key,
    required this.icon,
    required this.color,
    this.size = 40,
    this.iconSize = 22,
    this.backgroundAlpha = 0.10,
    this.borderRadius = 12,
  });

  final IconData icon;
  final Color color;
  final double size;
  final double iconSize;
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
      child: Icon(icon, color: color, size: iconSize),
    );
  }
}
