import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:preconnect/pages/ui_kit.dart';

class ExamCountdownCard extends StatelessWidget {
  const ExamCountdownCard({
    super.key,
    required this.title,
    required this.targetDateTime,
    this.daysOnly = false,
  });

  final String title;
  final DateTime targetDateTime;
  final bool daysOnly;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: Stream<int>.periodic(const Duration(seconds: 1), (tick) => tick),
      builder: (context, snapshot) {
        final now = DateTime.now();
        final remaining = targetDateTime.difference(now);
        final dateTimeLabel = _formatSubtitle(targetDateTime, now);
        return BracuCard(
          child: Row(
            children: [
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
              _ExamCountdownDigital(remaining: remaining, daysOnly: daysOnly),
            ],
          ),
        );
      },
    );
  }

  String _formatSubtitle(DateTime target, DateTime now) {
    final date = DateFormat('d MMMM, y').format(target);
    final time = DateFormat('h:mm a').format(target);
    return '$date • $time';
  }
}

class _ExamCountdownDigital extends StatelessWidget {
  const _ExamCountdownDigital({
    required this.remaining,
    required this.daysOnly,
  });

  final Duration remaining;
  final bool daysOnly;

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

    if (daysOnly) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [cell(days.toString(), 'Days')],
      );
    }

    final units = <({String value, String label})>[];
    if (days > 0) {
      units.add((value: days.toString(), label: 'Days'));
    }
    if (hours > 0) {
      units.add((value: hours.toString().padLeft(2, '0'), label: 'Hours'));
    }
    if (minutes > 0) {
      units.add((value: minutes.toString().padLeft(2, '0'), label: 'Minutes'));
    }
    units.add((value: seconds.toString().padLeft(2, '0'), label: 'Seconds'));

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < units.length; i++) ...[
          cell(units[i].value, units[i].label),
          if (i != units.length - 1) const SizedBox(width: 8),
        ],
      ],
    );
  }
}
