import 'package:material_ui/material_ui.dart';
import 'package:gap/gap.dart';
import 'package:preconnect/pages/ui_kit.dart';

class InfoLine extends StatelessWidget {
  const InfoLine({
    super.key,
    required this.label,
    required this.value,
    this.isValueBold = false,
    this.isLabelBold = false,
    this.valueColor,
    this.valueFlex = 6,
    this.valueWeight = FontWeight.w500,
  });

  final String label;
  final String value;
  final bool isValueBold;
  final bool isLabelBold;
  final Color? valueColor;
  final int valueFlex;
  final FontWeight valueWeight;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: Text(
              label,
              style: TextStyle(
                color: AppPalette.textSecondary(context),
                fontWeight: isLabelBold ? FontWeight.w700 : FontWeight.w500,
                fontSize: 14,
              ),
              textAlign: TextAlign.left,
            ),
          ),
          const Gap(12),
          Expanded(
            flex: valueFlex,
            child: Text(
              value,
              style: TextStyle(
                color: valueColor ?? AppPalette.textPrimary(context),
                fontWeight: isValueBold ? FontWeight.w700 : valueWeight,
                fontSize: 14,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}
