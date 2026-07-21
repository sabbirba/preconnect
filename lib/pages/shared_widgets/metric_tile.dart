import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:preconnect/pages/ui_kit.dart';

class MetricTile extends StatelessWidget {
  const MetricTile({
    super.key,
    required this.title,
    required this.value,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    this.borderRadius = 18,
  });

  final String title;
  final String value;
  final EdgeInsetsGeometry padding;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: BracuPalette.textSecondary(context).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (title.isNotEmpty)
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: BracuPalette.textSecondary(context),
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          if (title.isNotEmpty) const Gap(4),
          Text(
            value,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: BracuPalette.textPrimary(context),
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
