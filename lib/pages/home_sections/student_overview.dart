import 'package:flutter/material.dart';
import 'package:preconnect/pages/ui_kit.dart';

class StudentOverviewCard extends StatelessWidget {
  const StudentOverviewCard({
    super.key,
    required this.studentId,
    required this.phoneNumber,
    required this.studentEmail,
    required this.program,
    required this.onLogout,
    this.countdown,
  });

  final String studentId;
  final String phoneNumber;
  final String studentEmail;
  final String program;
  final Future<void> Function() onLogout;
  final Widget? countdown;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor =
        isDark ? BracuPalette.textPrimary(context) : Colors.white;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            color: isDark ? BracuPalette.card(context) : null,
            border: isDark
                ? Border.all(
                    color: BracuPalette.primary.withValues(alpha: 0.18),
                  )
                : null,
            gradient: isDark
                ? null
                : const LinearGradient(
                    colors: [Color(0xFF1E6BE3), Color(0xFF2C9DFF)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Student Overview',
                        style: TextStyle(
                          color: titleColor,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: onLogout,
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: isDark
                              ? BracuPalette.primary.withValues(alpha: 0.12)
                              : Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          Icons.logout,
                          size: 18,
                          color: isDark ? BracuPalette.primary : Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final half = (constraints.maxWidth - 12) / 2;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            _OverviewPill(
                              label: 'Student ID',
                              value: studentId,
                              width: half,
                              isDark: isDark,
                            ),
                            const SizedBox(width: 12),
                            _OverviewPill(
                              label: 'Phone Number',
                              value: phoneNumber,
                              width: half,
                              isDark: isDark,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _OverviewPill(
                          label: 'Student Email',
                          value: studentEmail,
                          width: constraints.maxWidth,
                          isDark: isDark,
                        ),
                        const SizedBox(height: 12),
                        _OverviewPill(
                          label: 'Program',
                          value: program,
                          width: constraints.maxWidth,
                          isDark: isDark,
                        ),
                      ],
                    );
                  },
                ),
                if (countdown != null) ...[
                  const SizedBox(height: 12),
                  countdown!,
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}

class _OverviewPill extends StatelessWidget {
  const _OverviewPill({
    required this.label,
    required this.value,
    required this.width,
    required this.isDark,
  });

  final String label;
  final String value;
  final double width;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final background = isDark
        ? BracuPalette.primary.withValues(alpha: 0.12)
        : Colors.white.withValues(alpha: 0.16);
    final borderColor = isDark
        ? BracuPalette.primary.withValues(alpha: 0.18)
        : Colors.white.withValues(alpha: 0.18);
    final labelColor = isDark
        ? BracuPalette.textSecondary(context)
        : Colors.white.withValues(alpha: 0.8);
    final valueColor =
        isDark ? BracuPalette.textPrimary(context) : Colors.white;
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: labelColor,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: valueColor,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
