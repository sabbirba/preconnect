import 'package:flutter/material.dart';
import 'package:preconnect/pages/ui_kit.dart';

class StudentOverviewCard extends StatelessWidget {
  const StudentOverviewCard({
    super.key,
    required this.studentId,
    required this.shortCode,
    required this.department,
    required this.currentSemester,
    required this.currentSessionSemesterId,
    required this.onOpenReward,
    required this.onOpenSettings,
    required this.onLogout,
    this.countdown,
  });

  final String studentId;
  final String shortCode;
  final String department;
  final String currentSemester;
  final String currentSessionSemesterId;
  final Future<void> Function() onOpenReward;
  final VoidCallback onOpenSettings;
  final Future<void> Function() onLogout;
  final Widget? countdown;

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
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _RewardIconButton(
                  icon: Icons.card_giftcard_outlined,
                  onTap: onOpenReward,
                ),
                const SizedBox(width: 8),
                _IconButton(
                  icon: Icons.settings_outlined,
                  onTap: onOpenSettings,
                ),
                const SizedBox(width: 8),
                _IconButton(icon: Icons.logout, onTap: onLogout),
              ],
            ),
            const SizedBox(height: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _OverviewHeader(
                  isDark: isDark,
                  studentId: studentId,
                  shortCode: shortCode,
                  department: department,
                  currentSemester: currentSemester,
                  currentSessionSemesterId: currentSessionSemesterId,
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

class _RewardIconButton extends StatefulWidget {
  const _RewardIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final Future<void> Function() onTap;

  @override
  State<_RewardIconButton> createState() => _RewardIconButtonState();
}

class _RewardIconButtonState extends State<_RewardIconButton> {
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
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        child: _isLoading ? _buildLoadingTile() : _buildButtonTile(),
      ),
    );
  }

  Widget _buildButtonTile() {
    return _buildTile(
      child: Icon(widget.icon, size: 18, color: BracuPalette.primary),
    );
  }

  Widget _buildLoadingTile() {
    return BracuShimmer(
      child: _buildTile(
        child: const BracuSkeletonBox(width: 18, height: 18, radius: 9),
      ),
    );
  }

  Widget _buildTile({required Widget child}) {
    return Container(
      width: 30,
      height: 30,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: BracuPalette.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      child: child,
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
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: BracuPalette.card(context),
        border: Border.all(color: baseBorderColor),
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
