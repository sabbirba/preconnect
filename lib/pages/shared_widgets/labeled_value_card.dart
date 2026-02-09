import 'package:flutter/material.dart';
import 'package:preconnect/pages/ui_kit.dart';

class LabeledValueCard extends StatelessWidget {
  const LabeledValueCard({
    super.key,
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        vertical: 10,
        horizontal: 12,
      ),
      decoration: BoxDecoration(
        color: BracuPalette.card(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: BracuPalette.primary.withValues(alpha: 0.14),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: BracuPalette.textSecondary(context),
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: BracuPalette.textPrimary(context),
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
