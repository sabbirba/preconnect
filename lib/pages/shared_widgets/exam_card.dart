import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/time_utils.dart';

class BracuExamCard extends StatelessWidget {
  const BracuExamCard({
    super.key,
    required this.courseCode,
    required this.sectionName,
    this.startTime,
    this.endTime,
    this.roomNumber,
    this.faculties,
    this.consumedSeat = 0,
    this.isHighlighted = false,
    this.highlightKey,
  });

  final String courseCode;
  final String? sectionName;
  final String? startTime;
  final String? endTime;
  final String? roomNumber;
  final String? faculties;
  final int consumedSeat;
  final bool isHighlighted;
  final Key? highlightKey;

  static String formatExamDate(String? input) {
    if (input == null || input.trim().isEmpty) return 'Not published yet';
    final raw = input.trim();
    final dt = BracuTime.parseDate(raw) ?? DateTime.tryParse(raw);
    if (dt == null) return raw;
    return DateFormat('EEEE, d MMMM, yyyy').format(dt);
  }

  static String formatExamTime(String? start, String? end) {
    final value = formatTimeRange(start, end).trim();
    if (value.isEmpty) return 'Not published yet';
    return value;
  }

  static String formatExamRoom(String? room) {
    final value = (room ?? '').trim();
    if (value.isEmpty) return 'TBA';
    return value;
  }

  @override
  Widget build(BuildContext context) {
    return BracuCard(
      key: highlightKey,
      isHighlighted: isHighlighted,
      highlightColor: BracuPalette.primary,
      child: Row(
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
                Text(
                  courseCode,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const Gap(4),
                Text(
                  formatExamTime(startTime, endTime),
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
                  formatExamRoom(roomNumber),
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: BracuPalette.textPrimary(context),
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if ((faculties ?? '').trim().isNotEmpty ||
                    consumedSeat > 0) ...[
                  const Gap(2),
                  Text.rich(
                    TextSpan(
                      children: [
                        if ((faculties ?? '').trim().isNotEmpty)
                          TextSpan(
                            text: faculties!.trim(),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: BracuPalette.textPrimary(context),
                            ),
                          ),
                        if (consumedSeat > 0)
                          TextSpan(
                            text:
                                '${(faculties ?? '').trim().isEmpty ? '' : ' '}($consumedSeat)',
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
      ),
    );
  }
}
