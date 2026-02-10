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
    final totalCredit = (advising['totalCredit'] ?? 'N/A').trim();
    final earnedCredit = (advising['earnedCredit'] ?? 'N/A').trim();
    final totalNum = double.tryParse(totalCredit) ?? 0;
    final earnedNum = double.tryParse(earnedCredit) ?? 0;
    final completionRatio =
        totalNum == 0 ? 0.0 : (earnedNum / totalNum).clamp(0.0, 1.0);
    final cgpa = (profile['cgpa'] ?? 'N/A').trim();
    final enrolledSemesterRaw = (profile['enrolledSemester'] ?? '').trim();
    final enrolledSemester = enrolledSemesterRaw.isNotEmpty
        ? formatSemesterTitle(enrolledSemesterRaw)
        : formatSemesterFromSessionId(
            (profile['enrolledSessionSemesterId'] ?? 'N/A').trim(),
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
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
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
                    cgpa.isEmpty ? 'N/A' : cgpa,
                  ),
                  child: Text(
                    cgpa.isEmpty ? 'N/A' : cgpa,
                    style: TextStyle(
                      color: textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
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
