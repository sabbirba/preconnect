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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = BracuPalette.textSecondary(context).withValues(
      alpha: isDark ? 0.35 : 0.18,
    );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: BracuPalette.card(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor),
        boxShadow: isDark
            ? const []
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
      ),
      child: _AcademicSummary(profile: profile, advising: advising),
    );
  }
}

class _AcademicSummary extends StatelessWidget {
  const _AcademicSummary({required this.profile, required this.advising});

  final Map<String, String?> profile;
  final Map<String, String?> advising;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = BracuPalette.textPrimary(context);
    final textSecondary = BracuPalette.textSecondary(context);
    final totalNum = _parseDouble(advising['totalCredit']);
    final earnedNum = _parseDouble(advising['earnedCredit']);
    final completionRatio =
        totalNum == 0 ? 0.0 : (earnedNum / totalNum).clamp(0.0, 1.0);
    final cgpa = _displayOrNA(profile['cgpa']);
    final semesterCount =
        int.tryParse((advising['noOfSemester'] ?? '').trim());
    final semesterCountDisplay =
        semesterCount == null ? 'N/A' : _ordinal(semesterCount);
    final enrolledSemester = _semesterTitle(
      profile['enrolledSemester'],
      profile['enrolledSessionSemesterId'],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'From',
                    style: TextStyle(
                      color: textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    enrolledSemester,
                    style: TextStyle(
                      color: textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    'Completed',
                    style: TextStyle(
                      color: textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    semesterCountDisplay,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'CGPA',
                    style: TextStyle(
                      color: textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: () => copyToClipboard(
                      context,
                      cgpa,
                    ),
                    child: Text(
                      cgpa,
                      style: TextStyle(
                        color: textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                'Credits completed',
                style: TextStyle(
                  color: textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              totalNum == 0
                  ? 'N/A'
                  : '${earnedNum.toStringAsFixed(0)} out of ${totalNum.toStringAsFixed(0)} • ${(completionRatio * 100).toStringAsFixed(0)}%',
              style: TextStyle(
                color: textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SimpleProgressBar(
          value: completionRatio,
          color: BracuPalette.primary,
          height: 8,
          backgroundAlpha: isDark ? 0.18 : 0.12,
        ),
      ],
    );
  }
}

String _displayOrNA(String? value) {
  final trimmed = (value ?? '').trim();
  return trimmed.isEmpty ? 'N/A' : trimmed;
}

double _parseDouble(String? value) {
  final raw = (value ?? '').trim();
  return double.tryParse(raw) ?? 0;
}

String _semesterTitle(String? raw, String? sessionId) {
  final cleaned = (raw ?? '').trim();
  if (cleaned.isNotEmpty) {
    return formatSemesterTitle(cleaned);
  }
  return formatSemesterFromSessionId((sessionId ?? 'N/A').trim());
}

String _ordinal(int value) {
  switch (value) {
    case 1:
      return 'First';
    case 2:
      return 'Second';
    case 3:
      return 'Third';
    case 4:
      return 'Fourth';
    case 5:
      return 'Fifth';
    case 6:
      return 'Sixth';
    case 7:
      return 'Seventh';
    case 8:
      return 'Eighth';
    case 9:
      return 'Ninth';
    case 10:
      return 'Tenth';
    case 11:
      return 'Eleventh';
    case 12:
      return 'Twelfth';
    case 13:
      return 'Thirteenth';
    case 14:
      return 'Fourteenth';
    case 15:
      return 'Fifteenth';
    case 16:
      return 'Sixteenth';
    case 17:
      return 'Seventeenth';
    case 18:
      return 'Eighteenth';
    case 19:
      return 'Nineteenth';
    case 20:
      return 'Twentieth';
    default:
      return 'Higher';
  }
}
