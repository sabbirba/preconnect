import 'package:flutter/material.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/token_storage.dart';

class StudentOverviewCard extends StatelessWidget {
  const StudentOverviewCard({
    super.key,
    required this.studentId,
    required this.shortCode,
    required this.department,
    required this.currentSemester,
    required this.currentSessionSemesterId,
    required this.onOpenSupport,
    required this.onOpenSettings,
    required this.onLogout,
    this.countdown,
    this.isLoading = false,
  });

  final String studentId;
  final String shortCode;
  final String department;
  final String currentSemester;
  final String currentSessionSemesterId;
  final Future<void> Function() onOpenSupport;
  final VoidCallback onOpenSettings;
  final Future<void> Function() onLogout;
  final Widget? countdown;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = BracuPalette.textPrimary(context);
    final hasProfileData =
        studentId.trim().isNotEmpty ||
        shortCode.trim().isNotEmpty ||
        department.trim().isNotEmpty ||
        currentSemester.trim().isNotEmpty ||
        currentSessionSemesterId.trim().isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ValueListenableBuilder<bool>(
              valueListenable: HomeCardPreferences.communityLinkNotifier,
              builder: (context, showCommunityLink, _) {
                return Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Overview',
                        style: TextStyle(
                          color: titleColor,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ),
                    if (showCommunityLink) ...[
                      const SizedBox(width: 8),
                      _SupportButton(onTap: onOpenSupport),
                    ],
                    const SizedBox(width: 8),
                    _IconButton(
                      icon: Icons.settings_outlined,
                      onTap: onOpenSettings,
                    ),
                    const SizedBox(width: 8),
                    _IconButton(icon: Icons.logout, onTap: onLogout),
                  ],
                );
              },
            ),
            const SizedBox(height: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (hasProfileData && !isLoading)
                  _OverviewHeader(
                    isDark: isDark,
                    studentId: studentId,
                    shortCode: shortCode,
                    department: department,
                    currentSemester: currentSemester,
                    currentSessionSemesterId: currentSessionSemesterId,
                  )
                else
                  _OverviewLoadingShimmer(
                    child: _OverviewLoadingCard(isDark: isDark),
                  ),
                if (countdown != null) ...[
                  const SizedBox(height: 10),
                  countdown!,
                ],
              ],
            ),
          ],
        ),
      ],
    );
  }
}

class _OverviewLoadingShimmer extends StatelessWidget {
  const _OverviewLoadingShimmer({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Shimmer.of(context) == null ? Shimmer(child: child) : child;
  }
}

class _OverviewLoadingCard extends StatelessWidget {
  const _OverviewLoadingCard({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final borderColor = BracuPalette.textSecondary(
      context,
    ).withValues(alpha: isDark ? 0.35 : 0.18);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: BracuPalette.card(context),
        border: Border.all(color: borderColor),
      ),
      child: SizedBox(
        height: 54,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final maxWidth = constraints.maxWidth;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ShimmerContainer(width: maxWidth * 0.62, height: 14),
                const SizedBox(height: 6),
                ShimmerContainer(width: maxWidth * 0.88, height: 11),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _IconButton extends StatelessWidget {
  const _IconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: BracuPalette.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, size: 18, color: BracuPalette.primary),
      ),
    );
  }
}

class _SupportButton extends StatefulWidget {
  const _SupportButton({required this.onTap});

  final Future<void> Function() onTap;

  @override
  State<_SupportButton> createState() => _SupportButtonState();
}

class _SupportButtonState extends State<_SupportButton> {
  bool _isLoading = false;

  Future<void> _handleTap() async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
    });
    try {
      await widget.onTap();
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: _isLoading ? null : _handleTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 9),
        decoration: BoxDecoration(
          color: BracuPalette.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.volunteer_activism_rounded,
              size: 16,
              color: BracuPalette.primary,
            ),
            const SizedBox(width: 6),
            Text(
              'Support',
              style: TextStyle(
                color: BracuPalette.primary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OverviewHeader extends StatelessWidget {
  const _OverviewHeader({
    required this.isDark,
    required this.studentId,
    required this.shortCode,
    required this.department,
    required this.currentSemester,
    required this.currentSessionSemesterId,
  });

  final bool isDark;
  final String studentId;
  final String shortCode;
  final String department;
  final String currentSemester;
  final String currentSessionSemesterId;

  @override
  Widget build(BuildContext context) {
    final baseBorderColor = BracuPalette.textSecondary(
      context,
    ).withValues(alpha: isDark ? 0.35 : 0.18);
    final normalizedSemester = formatSemesterTitle(currentSemester);
    final fallbackSemester = formatSemesterFromSessionId(
      currentSessionSemesterId,
    );
    final displaySemester = normalizedSemester.isNotEmpty
        ? normalizedSemester
        : (fallbackSemester.isNotEmpty ? fallbackSemester : '');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: _overviewCardDecoration(
        context,
        borderColor: baseBorderColor,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _headerTitle(
                    shortCode: shortCode,
                    studentId: studentId,
                    semester: displaySemester,
                  ),
                  style: TextStyle(
                    color: BracuPalette.textPrimary(context),
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  department.isEmpty ? '' : department,
                  overflow: TextOverflow.fade,
                  softWrap: true,
                  style: TextStyle(
                    color: BracuPalette.textSecondary(context),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _headerTitle({
    required String shortCode,
    required String studentId,
    required String semester,
  }) {
    final left = shortCode.isNotEmpty
        ? shortCode
        : (studentId.isEmpty ? '' : studentId);
    final right = semester.isEmpty ? '' : semester;
    return '${left.toUpperCase()} ${right.toUpperCase()}'.trim();
  }
}

BoxDecoration _overviewCardDecoration(
  BuildContext context, {
  required Color borderColor,
}) {
  return BoxDecoration(
    borderRadius: BorderRadius.circular(14),
    color: BracuPalette.card(context),
    border: Border.all(color: borderColor),
  );
}
