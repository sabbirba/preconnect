import 'package:flutter/material.dart';
import 'package:preconnect/pages/shared_widgets/progress_bar.dart';
import 'package:preconnect/pages/ui_kit.dart';

class AcademicSummaryCard extends StatelessWidget {
  const AcademicSummaryCard({
    super.key,
    required this.profile,
    required this.advising,
  });

  final Map<String, String?> profile;
  final Map<String, String?> advising;

  @override
  Widget build(BuildContext context) {
    return BracuCard(
      child: _AcademicSummary(profile: profile, advising: advising),
    );
  }
}

class _AcademicSummary extends StatelessWidget {
  const _AcademicSummary({required this.profile, required this.advising});

  final Map<String, String?> profile;
  final Map<String, String?> advising;

  bool get _hasAdvisingData {
    return advising.values.any((value) => value != null && value.trim().isNotEmpty);
  }

  @override
  Widget build(BuildContext context) {
    final advisingPhase = _formatAdvisingPhase(advising['advisingPhase']);
    final advisingStart = formatDate(advising['advisingStartDate']);
    final advisingEnd = formatDate(advising['advisingEndDate']);
    final advisingDate = advisingStart == 'N/A' && advisingEnd == 'N/A'
        ? 'N/A'
        : (advisingStart == advisingEnd
            ? advisingStart
            : '$advisingStart - $advisingEnd');
    final totalCredit = (advising['totalCredit'] ?? 'N/A').trim();
    final earnedCredit = (advising['earnedCredit'] ?? 'N/A').trim();
    final totalNum = double.tryParse(totalCredit) ?? 0;
    final earnedNum = double.tryParse(earnedCredit) ?? 0;
    final completionRatio =
        totalNum == 0 ? null : (earnedNum / totalNum).clamp(0.0, 1.0);
    final completion =
        completionRatio == null ? 'N/A' : '${(completionRatio * 100).toStringAsFixed(0)}%';
    final cgpa = (profile['cgpa'] ?? 'N/A').trim();
    final currentSemester = (profile['currentSemester'] ?? '').trim().isNotEmpty
        ? (profile['currentSemester'] ?? '').trim()
        : _formatSession(
            (profile['currentSessionSemesterId'] ?? 'N/A').trim(),
          );
    final fromSemester = (profile['enrolledSemester'] ?? '').trim().isNotEmpty
        ? (profile['enrolledSemester'] ?? '').trim()
        : _formatSession(
            (profile['enrolledSessionSemesterId'] ?? 'N/A').trim(),
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _BlueMetric(
                      label: 'Current Semester',
                      value: currentSemester,
                      alignRight: false,
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 40,
                    color: BracuPalette.primary.withValues(alpha: 0.18),
                  ),
                  Expanded(
                    child: _BlueMetric(
                      label: 'From Semester',
                      value: fromSemester,
                      alignRight: true,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SimpleProgressBar(
                value: completionRatio ?? 0,
                color: BracuPalette.primary,
                height: 8,
                backgroundAlpha: 0.12,
              ),
              const SizedBox(height: 10),
              Text(
                completionRatio == null
                    ? 'Completion data not available'
                    : 'You have completed ${earnedNum.toStringAsFixed(0)} of ${totalNum.toStringAsFixed(0)} credits ($completion) in ${_formatShortCode(profile['shortCode'])}, with a CGPA of ${cgpa.isEmpty ? 'N/A' : cgpa}, across ${(advising['noOfSemester'] ?? 'N/A').trim()} semesters.',
                style: TextStyle(
                  color: BracuPalette.textPrimary(context),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final half = (constraints.maxWidth - 12) / 2;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                if (_hasAdvisingData) ...[
                  _MiniField(
                    label: 'Advising Phase',
                    value: advisingPhase,
                    width: half,
                  ),
                  _MiniField(
                    label: 'Advising Date',
                    value: advisingDate,
                    width: half,
                  ),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

class _MiniField extends StatelessWidget {
  const _MiniField({
    required this.label,
    required this.value,
    required this.width,
  });

  final String label;
  final String value;
  final double width;

  @override
  Widget build(BuildContext context) {
    final textSecondary = BracuPalette.textSecondary(context);
    final textPrimary = BracuPalette.textPrimary(context);
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _BlueMetric extends StatelessWidget {
  const _BlueMetric({
    required this.label,
    required this.value,
    required this.alignRight,
  });

  final String label;
  final String value;
  final bool alignRight;

  @override
  Widget build(BuildContext context) {
    final textSecondary = BracuPalette.textSecondary(context);
    final textPrimary = BracuPalette.textPrimary(context);
    return Column(
      crossAxisAlignment:
          alignRight ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            color: textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

String _formatShortCode(String? raw) {
  final cleaned = (raw ?? '').trim();
  if (cleaned.isEmpty) return 'N/A';
  return cleaned.toUpperCase();
}

String _formatAdvisingPhase(String? raw) {
  final cleaned = (raw ?? '').trim();
  if (cleaned.isEmpty || cleaned == 'N/A') return 'N/A';
  final words = cleaned.split('_').where((w) => w.trim().isNotEmpty).toList();
  if (words.isEmpty) return cleaned;
  return words
      .map((w) {
        final lower = w.toLowerCase();
        return lower[0].toUpperCase() + lower.substring(1);
      })
      .join(' ');
}

String _formatSession(String raw) {
  if (raw.trim().isEmpty || raw.trim() == 'N/A') return 'N/A';
  final value = int.tryParse(raw.trim());
  if (value == null) return raw;
  final year = value ~/ 10;
  final code = value % 10;
  final label = switch (code) {
    1 => 'Spring',
    2 => 'Fall',
    3 => 'Summer',
    _ => 'Session',
  };
  return '$label $year';
}
