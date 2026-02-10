import 'package:flutter/material.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String studentOverviewPrefsKey = 'student_overview_expanded';

class StudentOverviewStore {
  static bool? _cachedExpanded;

  static bool get current => _cachedExpanded ?? true;

  static Future<void> load() async {
    if (_cachedExpanded != null) return;
    final prefs = await SharedPreferences.getInstance();
    _cachedExpanded = prefs.getBool(studentOverviewPrefsKey) ?? true;
  }

  static Future<void> set(bool value) async {
    _cachedExpanded = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(studentOverviewPrefsKey, value);
  }
}

class StudentOverviewCard extends StatefulWidget {
  const StudentOverviewCard({
    super.key,
    required this.studentId,
    required this.phoneNumber,
    required this.studentEmail,
    required this.program,
    required this.onLogout,
    required this.isExpanded,
    this.countdown,
    this.onExpandedChanged,
  });

  final String studentId;
  final String phoneNumber;
  final String studentEmail;
  final String program;
  final Future<void> Function() onLogout;
  final bool isExpanded;
  final Widget? countdown;
  final ValueChanged<bool>? onExpandedChanged;

  @override
  State<StudentOverviewCard> createState() => _StudentOverviewCardState();
}

class _StudentOverviewCardState extends State<StudentOverviewCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _expandController;

  @override
  void initState() {
    super.initState();
    _expandController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      value: widget.isExpanded ? 1.0 : 0.0,
    );
  }

  @override
  void didUpdateWidget(covariant StudentOverviewCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isExpanded != oldWidget.isExpanded) {
      if (widget.isExpanded) {
        _expandController.forward();
      } else {
        _expandController.reverse();
      }
    }
  }

  void _toggleExpanded() {
    widget.onExpandedChanged?.call(!widget.isExpanded);
  }

  @override
  void dispose() {
    _expandController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = BracuPalette.textPrimary(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Overview',
                    style: TextStyle(
                      color: titleColor,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: () => _toggleExpanded(),
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      widget.isExpanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      size: 20,
                      color: BracuPalette.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: widget.onLogout,
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.logout,
                      size: 18,
                      color: isDark
                          ? BracuPalette.primary
                          : BracuPalette.primary,
                    ),
                  ),
                ),
              ],
            ),
            ClipRect(
              child: SizeTransition(
                sizeFactor: _expandController,
                axisAlignment: -1,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
                                  value: widget.studentId,
                                  width: half,
                                  isDark: isDark,
                                ),
                                const SizedBox(width: 12),
                                _OverviewPill(
                                  label: 'Phone Number',
                                  value: widget.phoneNumber,
                                  width: half,
                                  isDark: isDark,
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            _OverviewPill(
                              label: 'Student Email',
                              value: widget.studentEmail,
                              width: constraints.maxWidth,
                              isDark: isDark,
                            ),
                            const SizedBox(height: 12),
                            _OverviewPill(
                              label: 'Program',
                              value: widget.program,
                              width: constraints.maxWidth,
                              isDark: isDark,
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            if (widget.countdown != null) ...[
              const SizedBox(height: 12),
              widget.countdown!,
            ],
          ],
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
        : BracuPalette.card(context);
    final borderColor = isDark
        ? BracuPalette.primary.withValues(alpha: 0.18)
        : Colors.black12;
    final labelColor = BracuPalette.textSecondary(context);
    final valueColor = BracuPalette.textPrimary(context);
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
