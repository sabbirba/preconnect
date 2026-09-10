import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/string_utils.dart';

class CourseTile extends StatelessWidget {
  const CourseTile({
    super.key,
    required this.code,
    required this.title,
    required this.credit,
    required this.isMandatory,
    required this.isPinned,
    required this.onTogglePin,
    this.gradeLabel,
    this.statusLabel,
    this.statusColor,
    this.codeFontFamily,
    this.bottomPadding = 12,
  });

  final String code;
  final String title;
  final double credit;
  final bool isMandatory;
  final bool isPinned;
  final VoidCallback onTogglePin;
  final String? gradeLabel;
  final String? statusLabel;
  final Color? statusColor;
  final String? codeFontFamily;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    final gradeLabelValue = gradeLabel;
    final statusLabelValue = statusLabel;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomPadding),
      child: AppCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (gradeLabelValue != null) ...[
              SectionBadge(
                label: gradeLabelValue,
                color: AppPalette.primary,
                size: 40,
                fontSize: 13,
              ),
              const Gap(12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(text: code),
                              WidgetSpan(
                                alignment: PlaceholderAlignment.middle,
                                child: Padding(
                                  padding: const EdgeInsets.only(left: 4),
                                  child: Tooltip(
                                    message: isPinned ? 'Unpin' : 'Pin to top',
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(999),
                                      onTap: onTogglePin,
                                      child: Icon(
                                        isPinned
                                            ? Icons.star_rounded
                                            : Icons.star_outline_rounded,
                                        size: 16,
                                        color: isPinned
                                            ? AppPalette.favorite
                                            : AppPalette.textSecondary(context),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          style: TextStyle(
                            color: AppPalette.textPrimary(context),
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            fontFamily: codeFontFamily,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Gap(3),
                  Text(
                    title.isEmpty ? '--' : title,
                    style: TextStyle(
                      color: AppPalette.textSecondary(context),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const Gap(12),
            SizedBox(
              width: 96,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${formatCredit(credit)} credits',
                    style: TextStyle(
                      color: AppPalette.textPrimary(context),
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Gap(1),
                  Text(
                    isMandatory ? 'Required' : 'Optional',
                    style: TextStyle(
                      color: isMandatory
                          ? AppPalette.warning
                          : AppPalette.accent,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (statusLabelValue != null) ...[
                    const Gap(2),
                    Text(
                      statusLabelValue,
                      style: TextStyle(
                        color: statusColor ?? AppPalette.accent,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
