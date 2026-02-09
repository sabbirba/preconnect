import 'package:flutter/material.dart';
import 'package:preconnect/model/attendance_info.dart';
import 'package:preconnect/pages/shared_widgets/progress_bar.dart';
import 'package:preconnect/pages/ui_kit.dart';

class AttendanceGraph extends StatelessWidget {
  const AttendanceGraph({super.key, required this.attendances});

  final List<AttendanceInfo> attendances;

  @override
  Widget build(BuildContext context) {
    final textSecondary = BracuPalette.textSecondary(context);
    final textPrimary = BracuPalette.textPrimary(context);
    return BracuCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: attendances.map((att) {
          final percent = att.totalClasses == 0
              ? 0.0
              : (att.attend / att.totalClasses) * 100;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${att.courseCode} • ${att.courseName}',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${percent.toStringAsFixed(0)}%',
                      style: TextStyle(
                        color: textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                SimpleProgressBar(
                  value: percent / 100,
                  color: BracuPalette.primary,
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}
