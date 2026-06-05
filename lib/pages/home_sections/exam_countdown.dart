import 'package:flutter/material.dart';
import 'package:preconnect/pages/ui_kit.dart';

class ExamCountdownCard extends StatelessWidget {
  const ExamCountdownCard({
    super.key,
    required this.title,
    required this.targetDateTime,
    this.subtitle,
  });

  final String title;
  final DateTime targetDateTime;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: Stream<int>.periodic(const Duration(minutes: 1), (tick) => tick),
      builder: (context, snapshot) {
        final now = DateTime.now();
        final remaining = targetDateTime.difference(now);
        final dateTimeLabel = subtitle ?? _formatSubtitle(targetDateTime, now);
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
              BracuCountdownDigital(remaining: remaining),
            ],
          ),
        );
      },
    );
  }

  String _formatSubtitle(DateTime target, DateTime now) {
    return formatDateTimeLabel(target, includeYear: false);
  }
}
