import 'package:flutter/material.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/pages/shared_widgets/section_badge.dart';

class ExamCountdownCard extends StatelessWidget {
  const ExamCountdownCard({
    super.key,
    required this.title,
    required this.dateTimeLabel,
    required this.countdownValue,
    required this.remaining,
  });

  final String title;
  final String dateTimeLabel;
  final String countdownValue;
  final Duration remaining;

  @override
  Widget build(BuildContext context) {
    return BracuCard(
      child: Row(
        children: [
          SectionBadge(
            label: countdownValue,
            color: BracuPalette.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: BracuPalette.textPrimary(context),
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  dateTimeLabel,
                  style: TextStyle(
                    color: BracuPalette.textSecondary(context),
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          _ExamCountdownDigital(remaining: remaining),
        ],
      ),
    );
  }
}

class _ExamCountdownDigital extends StatelessWidget {
  const _ExamCountdownDigital({required this.remaining});

  final Duration remaining;

  @override
  Widget build(BuildContext context) {
    final totalSeconds = remaining.inSeconds;
    final safeSeconds = totalSeconds < 0 ? 0 : totalSeconds;
    final days = safeSeconds ~/ 86400;
    final hours = (safeSeconds ~/ 3600) % 24;
    final minutes = (safeSeconds ~/ 60) % 60;
    final seconds = safeSeconds % 60;

    Widget cell(String value, String label) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: TextStyle(
              color: BracuPalette.textPrimary(context),
              fontWeight: FontWeight.w700,
              fontSize: 14,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: BracuPalette.textSecondary(context),
              fontWeight: FontWeight.w600,
              fontSize: 10,
            ),
          ),
        ],
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        cell(days.toString(), 'Days'),
        const SizedBox(width: 8),
        cell(hours.toString().padLeft(2, '0'), 'Hours'),
        const SizedBox(width: 8),
        cell(minutes.toString().padLeft(2, '0'), 'Minutes'),
        const SizedBox(width: 8),
        cell(seconds.toString().padLeft(2, '0'), 'Seconds'),
      ],
    );
  }
}
