part of 'package:preconnect/pages/ui_kit.dart';

class SectionsErrorState extends StatelessWidget {
  const SectionsErrorState({
    super.key,
    required this.title,
    required this.message,
    required this.onRetry,
  });

  final String title;
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 40,
              color: BracuPalette.textSecondary(context),
            ),
            const Gap(12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: BracuPalette.textPrimary(context),
              ),
            ),
            const Gap(6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: BracuPalette.textSecondary(context),
              ),
            ),
            const Gap(16),
            BracuActionButton(
              onPressed: onRetry,
              icon: Icons.refresh_rounded,
              label: 'Retry',
            ),
          ],
        ),
      ),
    );
  }
}

class SectionListCard extends StatelessWidget {
  const SectionListCard({
    super.key,
    required this.label,
    required this.sections,
    this.emptyMessage,
  });

  final String label;
  final List<Section> sections;
  final String? emptyMessage;

  static String _shortDay(String day) {
    if (day.length < 3) return day;
    return '${day.substring(0, 1)}${day.substring(1, 3).toLowerCase()}';
  }

  @override
  Widget build(BuildContext context) {
    final borderColor = BracuPalette.textSecondary(
      context,
    ).withValues(alpha: 0.22);
    final cardColor = BracuPalette.card(context).withValues(alpha: 0.35);

    if (sections.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: cardColor,
          border: Border.all(color: borderColor),
        ),
        child: Text(
          emptyMessage ?? '$label: no sections returned.',
          style: TextStyle(
            fontSize: 12,
            color: BracuPalette.textSecondary(context),
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: cardColor,
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label (${sections.length})',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: BracuPalette.textPrimary(context),
            ),
          ),
          const Gap(10),
          for (var i = 0; i < sections.length; i++) ...[
            _buildTile(context, sections[i]),
            if (i != sections.length - 1)
              Divider(
                height: 18,
                color: BracuPalette.textSecondary(
                  context,
                ).withValues(alpha: 0.14),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildTile(BuildContext context, Section section) {
    final scheduleLabel = section.sectionSchedule.classSchedules
        .map(
          (c) =>
              '${_shortDay(c.day)} ${formatTimeRange(c.startTime, c.endTime)}',
        )
        .join(', ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${section.courseCode} • ${section.sectionName}'
          '${section.sectionType != null ? ' (${section.sectionType})' : ''}',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: BracuPalette.textPrimary(context),
          ),
        ),
        const Gap(2),
        Text(
          '${section.faculties} • ${section.roomName} • '
          '${section.consumedSeat}/${section.capacity} seats',
          style: TextStyle(
            fontSize: 12,
            color: BracuPalette.textSecondary(context),
          ),
        ),
        if (scheduleLabel.isNotEmpty) ...[
          const Gap(2),
          Text(
            scheduleLabel,
            style: TextStyle(
              fontSize: 12,
              color: BracuPalette.textSecondary(context),
            ),
          ),
        ],
      ],
    );
  }
}
