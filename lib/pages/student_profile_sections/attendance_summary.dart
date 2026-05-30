import 'package:flutter/material.dart';
import 'package:preconnect/api/profile.dart';
import 'package:preconnect/pages/ui_kit.dart';

class AttendanceSummary extends StatelessWidget {
  const AttendanceSummary({super.key, required this.attendances});

  final List<AttendanceInfo> attendances;

  @override
  Widget build(BuildContext context) {
    return BracuCard(
      child: Column(
        children: List.generate(attendances.length, (index) {
          final att = attendances[index];
          final total = att.totalClasses;
          final percentage = total == 0 ? 0.0 : (att.attend / total) * 100;
          final isLast = index == attendances.length - 1;

          return Padding(
            padding: EdgeInsets.only(bottom: isLast ? 0 : 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${att.courseCode} • ${att.courseName}',
                        style: TextStyle(
                          color: BracuPalette.textPrimary(context),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _InlineAttendanceStat(
                      label: 'Present',
                      value: att.attend.toString(),
                    ),
                    _InlineAttendanceStat(
                      label: 'Absent',
                      value: att.missed.toString(),
                    ),
                    _InlineAttendanceStat(
                      label: 'Total',
                      value: total.toString(),
                    ),
                    _InlineAttendanceStat(
                      label: 'Percentage',
                      value: '${percentage.toStringAsFixed(0)}%',
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SimpleProgressBar(
                  value: (percentage / 100).clamp(0.0, 1.0),
                  color: BracuPalette.primary,
                ),
                if (!isLast) const SizedBox(height: 10),
                if (!isLast)
                  Divider(
                    height: 1,
                    color: BracuPalette.textSecondary(
                      context,
                    ).withValues(alpha: 0.16),
                  ),
              ],
            ),
          );
        }),
      ),
    );
  }
}

class _InlineAttendanceStat extends StatelessWidget {
  const _InlineAttendanceStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 8),
      decoration: BoxDecoration(
        color: BracuPalette.card(context),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: BracuPalette.primary.withValues(alpha: 0.14)),
      ),
      child: RichText(
        text: TextSpan(
          style: TextStyle(
            color: BracuPalette.textSecondary(context),
            fontSize: 11,
          ),
          children: [
            TextSpan(text: '$label: '),
            TextSpan(
              text: value,
              style: TextStyle(
                color: BracuPalette.textPrimary(context),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
