import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:preconnect/model/section_info.dart' as section;
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/ramadan.dart';

class ScheduleEntryCard extends StatelessWidget {
  const ScheduleEntryCard({
    super.key,
    required this.sectionName,
    required this.courseCode,
    required this.schedule,
    required this.isRamadan,
    this.roomNumber,
    this.faculties,
    this.consumedSeat,
    this.courseType,
    this.highlighted = false,
    this.highlightColor = BracuPalette.primary,
    this.wrapInCard = true,
    this.onTap,
  });

  final String? sectionName;
  final String courseCode;
  final section.ClassSchedule schedule;
  final bool isRamadan;
  final String? roomNumber;
  final String? faculties;
  final int? consumedSeat;
  final String? courseType;
  final bool highlighted;
  final Color highlightColor;
  final bool wrapInCard;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final adjusted = RamadanTiming.adjustRange(
      schedule.startTime,
      schedule.endTime,
      isRamadan: isRamadan,
    );
    final courseTypeLabel = (courseType ?? '').trim();
    final normalizedCourseType = courseTypeLabel.isNotEmpty
        ? courseTypeLabel[0].toUpperCase() +
              courseTypeLabel.substring(1).toLowerCase()
        : '';
    final facultyLabel = (faculties ?? '').trim();
    final consumedLabel = consumedSeat == null ? '' : '($consumedSeat)';
    final roomLabel = (roomNumber ?? '').trim();

    final content = LayoutBuilder(
      builder: (context, constraints) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SectionBadge(
              label: formatSectionBadge(sectionName),
              color: BracuPalette.primary,
            ),
            const Gap(12),
            Expanded(
              flex: 7,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: courseCode.trim(),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        if (normalizedCourseType.isNotEmpty)
                          TextSpan(
                            text: ' $normalizedCourseType',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: BracuPalette.textSecondary(context),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const Gap(4),
                  Text(
                    formatTimeRange(adjusted.startTime, adjusted.endTime),
                    style: TextStyle(
                      color: BracuPalette.textPrimary(context),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const Gap(12),
            Expanded(
              flex: 4,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    roomLabel,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: BracuPalette.textPrimary(context),
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (facultyLabel.isNotEmpty || consumedLabel.isNotEmpty) ...[
                    const Gap(2),
                    Text.rich(
                      TextSpan(
                        children: [
                          if (facultyLabel.isNotEmpty)
                            TextSpan(
                              text: facultyLabel,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: BracuPalette.textPrimary(context),
                              ),
                            ),
                          if (consumedLabel.isNotEmpty)
                            TextSpan(
                              text:
                                  '${facultyLabel.isEmpty ? '' : ' '}$consumedLabel',
                              style: TextStyle(
                                fontSize: 12,
                                color: BracuPalette.textSecondary(context),
                              ),
                            ),
                        ],
                      ),
                      textAlign: TextAlign.right,
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );

    if (!wrapInCard) {
      return content;
    }
    final card = BracuCard(
      isHighlighted: highlighted,
      highlightColor: highlightColor,
      child: content,
    );
    if (onTap == null) {
      return card;
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: card,
      ),
    );
  }
}
