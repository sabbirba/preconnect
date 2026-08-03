part of 'package:preconnect/pages/ui_kit.dart';

class QuickAccessItem {
  const QuickAccessItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
}

List<QuickAccessItem> defaultQuickAccessItems({
  required void Function(HomeTab tab) onTap,
}) => <QuickAccessItem>[
  QuickAccessItem(
    icon: Icons.person_outline,
    title: 'Profile',
    subtitle: 'Info & ID',
    color: const Color(0xFF1E6BE3),
    onTap: () => onTap(HomeTab.profile),
  ),
  QuickAccessItem(
    icon: Icons.schedule_outlined,
    title: 'Class',
    subtitle: 'Schedules',
    color: const Color(0xFF22B573),
    onTap: () => onTap(HomeTab.studentSchedule),
  ),
  QuickAccessItem(
    icon: Icons.event_note_outlined,
    title: 'Exam',
    subtitle: 'Schedules',
    color: const Color(0xFF7C56FF),
    onTap: () => onTap(HomeTab.examSchedule),
  ),
  QuickAccessItem(
    icon: Icons.alarm_outlined,
    title: 'Alarm',
    subtitle: 'Reminders',
    color: const Color(0xFFFF8A34),
    onTap: () => onTap(HomeTab.alarms),
  ),
  QuickAccessItem(
    icon: Icons.event_note_outlined,
    title: 'Custom',
    subtitle: 'Schedules',
    color: const Color(0xFF1E6BE3),
    onTap: () => onTap(HomeTab.personalSchedules),
  ),
  QuickAccessItem(
    icon: Icons.people_outline_rounded,
    title: 'Friends',
    subtitle: 'Schedules',
    color: const Color(0xFF5B8DEF),
    onTap: () => onTap(HomeTab.friendSchedule),
  ),
  QuickAccessItem(
    icon: Icons.trending_up_rounded,
    title: 'Degree',
    subtitle: 'Progress',
    color: const Color(0xFF2C9DFF),
    onTap: () => onTap(HomeTab.degreeProgress),
  ),
  QuickAccessItem(
    icon: Icons.developer_mode_outlined,
    title: 'Devs',
    subtitle: 'Support',
    color: const Color(0xFF2C9DFF),
    onTap: () => onTap(HomeTab.devs),
  ),
  QuickAccessItem(
    icon: Icons.local_library_outlined,
    title: 'Library',
    subtitle: 'Libsync',
    color: const Color(0xFF007ACC),
    onTap: () => onTap(HomeTab.libSync),
  ),
  QuickAccessItem(
    icon: Icons.computer_outlined,
    title: 'Free',
    subtitle: 'Labs',
    color: const Color(0xFF00A8E8),
    onTap: () => onTap(HomeTab.freeLabs),
  ),
  QuickAccessItem(
    icon: Icons.insights_outlined,
    title: 'Seat',
    subtitle: 'Status',
    color: const Color(0xFF00A8E8),
    onTap: () => onTap(HomeTab.seatStatus),
  ),
  QuickAccessItem(
    icon: Icons.directions_bus_rounded,
    title: 'Bus',
    subtitle: 'Routes',
    color: const Color(0xFF00A8E8),
    onTap: () => onTap(HomeTab.bus),
  ),
  QuickAccessItem(
    icon: Icons.local_printshop_outlined,
    title: 'Printer',
    subtitle: 'Campus',
    color: const Color(0xFF22B573),
    onTap: () => onTap(HomeTab.campusPrinter),
  ),
  QuickAccessItem(
    icon: Icons.library_books_outlined,
    title: 'DSpace',
    subtitle: 'Repository',
    color: const Color(0xFF3CA947),
    onTap: () => onTap(HomeTab.dspace),
  ),
  QuickAccessItem(
    icon: Icons.calendar_today_outlined,
    title: 'Events',
    subtitle: 'Academic',
    color: const Color(0xFF00A86B),
    onTap: () => onTap(HomeTab.calendar),
  ),
];

class QuickAccessGrid extends StatefulWidget {
  const QuickAccessGrid({
    super.key,
    required this.items,
    this.initialVisibleCount = 8,
    this.collapsedPreviewCount = 4,
  });

  final List<QuickAccessItem> items;
  final int initialVisibleCount;
  final int collapsedPreviewCount;

  @override
  State<QuickAccessGrid> createState() => _QuickAccessGridState();
}

class _QuickAccessGridState extends State<QuickAccessGrid> {
  bool _expanded = false;

  void _toggleExpanded() {
    setState(() {
      _expanded = !_expanded;
    });
  }

  @override
  Widget build(BuildContext context) {
    final staticItems = widget.items.take(widget.initialVisibleCount).toList();
    final expandableItems = widget.items
        .skip(widget.initialVisibleCount)
        .toList();
    final dividerColor = Theme.of(context).dividerColor.withValues(alpha: 0.12);
    final primaryColor = Theme.of(context).colorScheme.primary;

    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = quickAccessGridLayout(constraints.maxWidth);

        Widget buildCard(QuickAccessItem item, {VoidCallback? onTap}) {
          return QuickAccessCard(
            width: layout.itemWidth,
            icon: item.icon,
            title: item.title,
            subtitle: item.subtitle,
            color: item.color,
            onTap: onTap ?? item.onTap,
          );
        }

        Widget buildWrap(List<QuickAccessItem> items, {VoidCallback? onTap}) {
          return Center(
            child: Wrap(
              alignment: WrapAlignment.center,
              runAlignment: WrapAlignment.center,
              spacing: layout.spacing,
              runSpacing: layout.spacing,
              children: items
                  .map((item) => buildCard(item, onTap: onTap))
                  .toList(),
            ),
          );
        }

        if (expandableItems.isEmpty) {
          return buildWrap(staticItems);
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            buildWrap(staticItems),
            AnimatedSize(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              alignment: Alignment.topCenter,
              child: _expanded
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: EdgeInsets.only(top: layout.spacing),
                          child: buildWrap(expandableItems),
                        ),
                        const Gap(16),
                        _buildToggle(
                          label: 'See Less',
                          rotated: true,
                          dividerColor: dividerColor,
                          primaryColor: primaryColor,
                        ),
                      ],
                    )
                  : Stack(
                      alignment: Alignment.bottomCenter,
                      children: [
                        GestureDetector(
                          onTap: _toggleExpanded,
                          behavior: HitTestBehavior.opaque,
                          child: IgnorePointer(
                            child: Padding(
                              padding: EdgeInsets.only(
                                top: layout.spacing,
                                bottom: 12,
                              ),
                              child: ClipRect(
                                child: Align(
                                  alignment: Alignment.topCenter,
                                  heightFactor: 0.5,
                                  child: ShaderMask(
                                    shaderCallback: (rect) {
                                      return const LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: [
                                          Colors.black,
                                          Colors.transparent,
                                        ],
                                        stops: [0.0, 1.0],
                                      ).createShader(
                                        Rect.fromLTRB(
                                          0,
                                          0,
                                          rect.width,
                                          rect.height,
                                        ),
                                      );
                                    },
                                    blendMode: BlendMode.dstIn,
                                    child: buildWrap(
                                      expandableItems
                                          .take(widget.collapsedPreviewCount)
                                          .toList(),
                                      onTap: () {},
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        _buildToggle(
                          label: 'See More',
                          rotated: false,
                          dividerColor: dividerColor,
                          primaryColor: primaryColor,
                        ),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildToggle({
    required String label,
    required bool rotated,
    required Color dividerColor,
    required Color primaryColor,
  }) {
    return InkWell(
      onTap: _toggleExpanded,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: dividerColor, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: primaryColor,
              ),
            ),
            const Gap(4),
            AnimatedRotation(
              turns: rotated ? 0.5 : 0.0,
              duration: const Duration(milliseconds: 250),
              child: Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 16,
                color: primaryColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
