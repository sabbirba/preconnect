part of 'package:preconnect/pages/home.dart';

extension _HomeDashboardView on _HomeDashboardState {
  Widget _buildHomeDashboardView(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgTop = isDark ? Colors.black : _HomeDashboardState._bgTop;
    final bgBottom = isDark ? Colors.black : _HomeDashboardState._bgBottom;

    return ValueListenableBuilder(
      valueListenable: HomeCardPreferences.decorationNotifier,
      builder: (context, decorationsEnabled, child) {
        final baseColor = Theme.of(context).scaffoldBackgroundColor;
        return Container(
          decoration: decorationsEnabled
              ? BoxDecoration(
                  color: baseColor,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [bgTop, bgBottom],
                  ),
                )
              : BoxDecoration(color: baseColor),
          child: SafeArea(
            child: Stack(
              children: [
                if (decorationsEnabled)
                  Positioned(
                    top: -80,
                    right: -60,
                    child: DecorBlob(
                      color: _HomeDashboardState._primary.withValues(
                        alpha: 0.12,
                      ),
                      size: 200,
                    ),
                  ),
                if (decorationsEnabled)
                  Positioned(
                    bottom: -90,
                    left: -70,
                    child: DecorBlob(
                      color: _HomeDashboardState._accent.withValues(
                        alpha: 0.10,
                      ),
                      size: 220,
                    ),
                  ),
                Column(
                  children: [
                    Expanded(
                      child: FutureBuilder<_HomeData>(
                        future: _future,
                        builder: (context, snapshot) {
                          final data = _latestData ?? snapshot.data;
                          final isLoading =
                              snapshot.connectionState ==
                                  ConnectionState.waiting &&
                              data == null;
                          if (isLoading) {
                            return BracuRefreshScroll(
                              onRefresh: _handleRefresh,
                              showScrollTopButton: false,
                              padding: const EdgeInsets.fromLTRB(
                                20,
                                16,
                                20,
                                28,
                              ),
                              child: _HomeDashboardLoadingShell(
                                onOpenSupport: () =>
                                    showBracuFundingSupportSheet(context),
                                onOpenSettings: () =>
                                    widget.onNavigate(HomeTab.settings),
                                onLogout: widget.onLogout,
                              ),
                            );
                          }

                          final profile =
                              data?.profile ?? const <String, String?>{};
                          final photoUrl = data?.photoUrl;
                          final cardVisibility =
                              data?.cardVisibility ??
                              HomeCardPreferences.defaults;
                          final fullName = (profile['fullName'] ?? '').trim();
                          final hasOverviewProfileData =
                              (profile['studentId'] ?? '').trim().isNotEmpty ||
                              (profile['shortCode'] ?? '').trim().isNotEmpty ||
                              (profile['departmentName'] ?? '')
                                  .trim()
                                  .isNotEmpty ||
                              (profile['currentSemester'] ?? '')
                                  .trim()
                                  .isNotEmpty ||
                              (profile['currentSessionSemesterId'] ?? '')
                                  .trim()
                                  .isNotEmpty;
                          final isOverviewLoading =
                              data == null || !hasOverviewProfileData;
                          final hasTopBarData =
                              fullName.isNotEmpty ||
                              (photoUrl ?? '').trim().isNotEmpty;
                          final isTopBarLoading =
                              data == null || !hasTopBarData;
                          final hasScheduleData = (data?.scheduleJson ?? '')
                              .trim()
                              .isNotEmpty;
                          final isTodayScheduleLoading =
                              cardVisibility.showTodaySchedule &&
                              (data == null || !hasScheduleData);
                          final ramadan =
                              data?.ramadan ??
                              const RamadanStatus(isRamadan: false);
                          final isRamadan = ramadan.isRamadan;
                          final nextCountdownTarget = _nextRamadanTarget(
                            sehri: ramadan.sehriEndsAt,
                            iftar: ramadan.iftarAt,
                          );
                          final holidayStatus =
                              data?.holiday ?? HolidayStatus.empty;
                          final isTodayHoliday = holidayStatus.isTodayHoliday;
                          final today = _todayName();
                          final todayDate = DateFormat(
                            'd MMMM, yyyy',
                          ).format(DateTime.now());
                          final todayEntries =
                              (data?.entries ?? [])
                                  .where(
                                    (e) =>
                                        normalizeWeekday(e.day) ==
                                        normalizeWeekday(today),
                                  )
                                  .toList()
                                ..sort(
                                  (a, b) =>
                                      _timeToMinutes(a.startTime) -
                                      _timeToMinutes(b.startTime),
                                );
                          final examWeekStatus = _todayExamWeekStatus(
                            data?.sections ?? const <section.Section>[],
                            data?.examOverrides ??
                                const <String, ExamScheduleOverride>{},
                          );
                          final isExamWeekActive = examWeekStatus.isActive;
                          final nextCountdown = _nextDeadlineCountdown(
                            data?.sections ?? const <section.Section>[],
                            data?.examOverrides ??
                                const <String, ExamScheduleOverride>{},
                            data?.personalSchedules ?? const <CustomSchedule>[],
                            data?.advisingInfo,
                          );
                          final todayExams = _todayExamEntries(
                            data?.sections ?? const <section.Section>[],
                            data?.examOverrides ??
                                const <String, ExamScheduleOverride>{},
                          );
                          final visibleEntries = isTodayHoliday
                              ? <_ScheduleEntry>[]
                              : (todayExams.isNotEmpty || isExamWeekActive
                                    ? <_ScheduleEntry>[]
                                    : todayEntries);
                          return BracuRefreshScroll(
                            onRefresh: _handleRefresh,
                            showScrollTopButton: false,
                            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (isTopBarLoading)
                                  const Shimmer(
                                    child: _HomeTopBarLoadingSkeleton(),
                                  )
                                else
                                  _TopBar(
                                    name: fullName,
                                    photoUrl: photoUrl,
                                    showNotificationsIcon:
                                        cardVisibility.showNotificationsIcon,
                                    onOpenNotifications: () => widget
                                        .onNavigate(HomeTab.notifications),
                                    onProfileTap: () =>
                                        widget.onNavigate(HomeTab.profile),
                                  ),
                                if (_captiveStatus?.state ==
                                    CaptiveWifiState.captive) ...[
                                  const SizedBox(height: 12),
                                  _CaptiveWifiBanner(
                                    statusCode: _captiveStatus?.httpStatusCode,
                                    onOpenLogin: _runBackgroundWifiConnect,
                                    isLoading: _isConnectingWifi,
                                  ),
                                ],
                                const SizedBox(height: 12),
                                StudentOverviewCard(
                                  studentId: profile['studentId'] ?? '',
                                  shortCode: profile['shortCode'] ?? '',
                                  department: profile['departmentName'] ?? '',
                                  currentSemester:
                                      profile['currentSemester'] ?? '',
                                  currentSessionSemesterId:
                                      profile['currentSessionSemesterId'] ?? '',
                                  onOpenSupport: () =>
                                      showBracuFundingSupportSheet(context),
                                  onOpenSettings: () =>
                                      widget.onNavigate(HomeTab.settings),
                                  onLogout: widget.onLogout,
                                  isLoading: isOverviewLoading,
                                  countdown:
                                      !cardVisibility.showExamCountdownCard ||
                                          nextCountdown == null
                                      ? null
                                      : InkWell(
                                          borderRadius: BorderRadius.circular(
                                            18,
                                          ),
                                          onTap: () => widget.onNavigate(
                                            nextCountdown.tab,
                                          ),
                                          child: ExamCountdownCard(
                                            title: nextCountdown.title,
                                            targetDateTime:
                                                nextCountdown.targetDateTime,
                                            subtitle: nextCountdown.subtitle,
                                          ),
                                        ),
                                ),
                                const SizedBox(height: 12),
                                const BracuFundingPromoDivider(),
                                const SizedBox(height: 12),
                                if (isTodayScheduleLoading) ...[
                                  const Shimmer(
                                    child: _TodayScheduleLoadingSkeleton(),
                                  ),
                                ] else if (cardVisibility
                                    .showTodaySchedule) ...[
                                  InkWell(
                                    onTap: () => widget.onNavigate(
                                      (todayExams.isNotEmpty ||
                                              isExamWeekActive)
                                          ? HomeTab.examSchedule
                                          : HomeTab.studentSchedule,
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            'Today is $today',
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                              color: BracuPalette.textPrimary(
                                                context,
                                              ),
                                            ),
                                          ),
                                        ),
                                        Text(
                                          todayDate,
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                            color: BracuPalette.textPrimary(
                                              context,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  if (todayExams.isNotEmpty)
                                    ...todayExams
                                        .take(3)
                                        .map(
                                          (exam) => Padding(
                                            padding: const EdgeInsets.only(
                                              bottom: 12,
                                            ),
                                            child: InkWell(
                                              onTap: () => widget.onNavigate(
                                                HomeTab.examSchedule,
                                              ),
                                              child: _ScheduleTile(
                                                title:
                                                    '${exam.courseCode} ${exam.type}',
                                                subtitle: formatTimeRange(
                                                  exam.startTime,
                                                  exam.endTime,
                                                ),
                                                trailing: exam.room,
                                                trailingSub: exam.faculties,
                                                badge: formatSectionBadge(
                                                  exam.sectionName,
                                                ),
                                                color:
                                                    _HomeDashboardState._accent,
                                                isHighlighted: false,
                                              ),
                                            ),
                                          ),
                                        ),
                                  if (todayExams.isEmpty &&
                                      (isTodayHoliday ||
                                          visibleEntries.isEmpty))
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 12,
                                      ),
                                      child: InkWell(
                                        onTap: () => widget.onNavigate(
                                          isExamWeekActive
                                              ? HomeTab.examSchedule
                                              : HomeTab.studentSchedule,
                                        ),
                                        child: _ScheduleTile(
                                          title: isExamWeekActive
                                              ? 'No classes today!'
                                              : isTodayHoliday
                                              ? 'National holiday'
                                              : 'No classes today!',
                                          subtitle: isExamWeekActive
                                              ? examWeekStatus.subtitle
                                              : isTodayHoliday
                                              ? holidayStatus.displayNames
                                              : 'Enjoy your day off.',
                                          badge: isExamWeekActive
                                              ? '--'
                                              : isTodayHoliday
                                              ? 'OFF'
                                              : '--',
                                          color: _HomeDashboardState._primary,
                                        ),
                                      ),
                                    )
                                  else if (visibleEntries.isNotEmpty)
                                    ...visibleEntries
                                        .take(3)
                                        .map(
                                          (entry) => Padding(
                                            padding: const EdgeInsets.only(
                                              bottom: 12,
                                            ),
                                            child: InkWell(
                                              onTap: () => widget.onNavigate(
                                                HomeTab.studentSchedule,
                                              ),
                                              child: _ScheduleTile(
                                                title: entry.courseCode,
                                                subtitle: formatTimeRange(
                                                  entry.startTime,
                                                  entry.endTime,
                                                ),
                                                trailing: entry.roomNumber,
                                                trailingSub: entry.faculties,
                                                badge: formatSectionBadge(
                                                  entry.sectionName,
                                                ),
                                                color: _HomeDashboardState
                                                    ._primary,
                                                isHighlighted: false,
                                              ),
                                            ),
                                          ),
                                        ),
                                ],
                                if (cardVisibility.showRamadanCard && isRamadan)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: BracuCard(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          if (nextCountdownTarget != null) ...[
                                            _RamadanTopCountdown(
                                              ramadanDay: ramadan.ramadanDay,
                                              targetLabel: nextCountdownTarget,
                                              targetTime:
                                                  nextCountdownTarget == 'Sehri'
                                                  ? ramadan.sehriEndsAt
                                                  : ramadan.iftarAt,
                                            ),
                                            Divider(
                                              height: 14,
                                              thickness: 1,
                                              color:
                                                  BracuPalette.textSecondary(
                                                    context,
                                                  ).withValues(
                                                    alpha:
                                                        Theme.of(
                                                              context,
                                                            ).brightness ==
                                                            Brightness.dark
                                                        ? 0.20
                                                        : 0.12,
                                                  ),
                                            ),
                                          ],
                                          if (ramadan.sehriEndsAt != null ||
                                              ramadan.iftarAt != null) ...[
                                            Row(
                                              children: [
                                                if (ramadan.sehriEndsAt != null)
                                                  Expanded(
                                                    child: _RamadanHeroTime(
                                                      label: 'Sehri',
                                                      value: BracuTime.format(
                                                        ramadan.sehriEndsAt,
                                                      ),
                                                    ),
                                                  ),
                                                if (ramadan.sehriEndsAt !=
                                                        null &&
                                                    ramadan.iftarAt != null)
                                                  const SizedBox(width: 10),
                                                if (ramadan.iftarAt != null)
                                                  Expanded(
                                                    child: _RamadanHeroTime(
                                                      label: 'Iftar',
                                                      value: BracuTime.format(
                                                        ramadan.iftarAt,
                                                      ),
                                                      alignRight: true,
                                                    ),
                                                  ),
                                              ],
                                            ),
                                            const SizedBox(height: 2),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ),
                                if (cardVisibility.showQuickAccessSection) ...[
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      const Expanded(
                                        child: _SectionTitle(
                                          title: 'Quick Access',
                                        ),
                                      ),
                                      Row(
                                        children: [
                                          InkWell(
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                            onTap: () async {
                                              await InAppReviewPrompt.openStoreListing();
                                            },
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 2,
                                                  ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  SizedBox(
                                                    width: 16,
                                                    child: Icon(
                                                      Icons.star_border_rounded,
                                                      size: 17,
                                                      color:
                                                          BracuPalette.textPrimary(
                                                            context,
                                                          ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Text(
                                                    'Rate',
                                                    softWrap: false,
                                                    style: TextStyle(
                                                      fontSize: 16,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color:
                                                          BracuPalette.textPrimary(
                                                            context,
                                                          ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          InkWell(
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                            onTap: () async {
                                              await SharePlus.instance.share(
                                                ShareParams(
                                                  uri: Uri.parse(
                                                    'https://play.google.com/store/apps/details?id=com.sabbirba.preconnect',
                                                  ),
                                                  subject:
                                                      'PreConnect • Prepare. Connect. Succeed.',
                                                ),
                                              );
                                            },
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 2,
                                                  ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  SizedBox(
                                                    width: 16,
                                                    child: Icon(
                                                      Icons.share_outlined,
                                                      size: 14,
                                                      color:
                                                          BracuPalette.textPrimary(
                                                            context,
                                                          ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Text(
                                                    'Share',
                                                    softWrap: false,
                                                    style: TextStyle(
                                                      fontSize: 16,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color:
                                                          BracuPalette.textPrimary(
                                                            context,
                                                          ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  LayoutBuilder(
                                    builder: (context, constraints) {
                                      return _buildQuickAccessGrid(
                                        maxWidth: constraints.maxWidth,
                                      );
                                    },
                                  ),
                                ],
                                const SizedBox(height: 12),
                                if (data == null)
                                  const Padding(
                                    padding: EdgeInsets.only(bottom: 12),
                                    child: _CampusMapLoadingSkeleton(),
                                  ),
                                if (cardVisibility.showCampusMapContacts) ...[
                                  BracuActionBannerCard(
                                    icon: Icons.location_on_rounded,
                                    title: 'Campus Map & Contacts',
                                    subtitle: 'Location and emergency contacts',
                                    iconColor: const Color(0xFF22B573),
                                    onTap: _openCampusMapSheet,
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildQuickAccessGrid({required double maxWidth}) {
    final layout = quickAccessGridLayout(maxWidth);
    return Center(
      child: Wrap(
        alignment: WrapAlignment.center,
        runAlignment: WrapAlignment.center,
        spacing: layout.spacing,
        runSpacing: layout.spacing,
        children: _quickAccessItems.map((item) {
          return QuickAccessCard(
            width: layout.itemWidth,
            icon: item.icon,
            title: item.title,
            subtitle: item.subtitle,
            color: item.color,
            onTap: () => widget.onNavigate(item.tab!),
          );
        }).toList(),
      ),
    );
  }

  List<_DashboardQuickAccess> get _quickAccessItems => <_DashboardQuickAccess>[
    _DashboardQuickAccess(
      tab: HomeTab.profile,
      icon: Icons.person_outline,
      title: 'Profile',
      subtitle: 'Info & ID',
      color: _HomeDashboardState._primary,
    ),
    _DashboardQuickAccess(
      tab: HomeTab.studentSchedule,
      icon: Icons.schedule_outlined,
      title: 'Class',
      subtitle: 'Schedules',
      color: _HomeDashboardState._accent,
    ),
    _DashboardQuickAccess(
      tab: HomeTab.examSchedule,
      icon: Icons.event_note_outlined,
      title: 'Exam',
      subtitle: 'Schedules',
      color: Color(0xFF7C56FF),
    ),
    _DashboardQuickAccess(
      tab: HomeTab.alarms,
      icon: Icons.alarm_outlined,
      title: 'Alarm',
      subtitle: 'Reminders',
      color: Color(0xFFFF8A34),
    ),
    _DashboardQuickAccess(
      tab: HomeTab.personalSchedules,
      icon: Icons.event_note_outlined,
      title: 'Custom',
      subtitle: 'Schedules',
      color: Color(0xFF1E6BE3),
    ),
    _DashboardQuickAccess(
      tab: HomeTab.friendSchedule,
      icon: Icons.people_outline_rounded,
      title: 'Friends',
      subtitle: 'Schedules',
      color: Color(0xFF5B8DEF),
    ),
    _DashboardQuickAccess(
      tab: HomeTab.degreeProgress,
      icon: Icons.trending_up_rounded,
      title: 'Degree',
      subtitle: 'Progress',
      color: Color(0xFF2C9DFF),
    ),
    _DashboardQuickAccess(
      tab: HomeTab.moreQuickAccess,
      icon: Icons.more_horiz_rounded,
      title: 'More',
      subtitle: 'Options',
      color: Color(0xFF00A8E8),
    ),
  ];
}

class _DashboardQuickAccess {
  const _DashboardQuickAccess({
    this.tab,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
  });

  final HomeTab? tab;
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
}

class _HomeDashboardLoadingShell extends StatelessWidget {
  const _HomeDashboardLoadingShell({
    required this.onOpenSupport,
    required this.onOpenSettings,
    required this.onLogout,
  });

  final Future<void> Function() onOpenSupport;
  final VoidCallback onOpenSettings;
  final Future<void> Function() onLogout;

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _HomeTopBarLoadingSkeleton(),
          const SizedBox(height: 12),
          StudentOverviewCard(
            studentId: '',
            shortCode: '',
            department: '',
            currentSemester: '',
            currentSessionSemesterId: '',
            onOpenSupport: onOpenSupport,
            onOpenSettings: onOpenSettings,
            onLogout: onLogout,
            isLoading: true,
          ),
          const SizedBox(height: 12),
          const _TodayScheduleLoadingSkeleton(),
          const _QuickAccessLoadingSkeleton(),
          const SizedBox(height: 12),
          const _CampusMapLoadingSkeleton(),
        ],
      ),
    );
  }
}

class _HomeTopBarLoadingSkeleton extends StatelessWidget {
  const _HomeTopBarLoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        ShimmerContainer(
          width: 42,
          height: 42,
          borderRadius: BorderRadius.all(Radius.circular(14)),
        ),
        SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ShimmerContainer(width: 92, height: 10),
              SizedBox(height: 8),
              ShimmerContainer(width: 148, height: 18),
            ],
          ),
        ),
        SizedBox(width: 12),
        ShimmerContainer(
          width: 44,
          height: 44,
          borderRadius: BorderRadius.all(Radius.circular(999)),
        ),
      ],
    );
  }
}

class _ActionBannerLoadingSkeleton extends StatelessWidget {
  const _ActionBannerLoadingSkeleton({required this.showTrailingIcon});

  final bool showTrailingIcon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final textWidth =
              constraints.maxWidth - 30 - 12 - (showTrailingIcon ? 36 : 0);
          final safeTextWidth = textWidth < 0 ? 0.0 : textWidth;
          final titleWidth = safeTextWidth * 0.58;
          final subtitleWidth = safeTextWidth * 0.82;
          return Row(
            children: [
              const ShimmerContainer(
                width: 30,
                height: 30,
                borderRadius: BorderRadius.all(Radius.circular(10)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ShimmerContainer(width: titleWidth, height: 15),
                    const SizedBox(height: 5),
                    ShimmerContainer(width: subtitleWidth, height: 11),
                  ],
                ),
              ),
              if (showTrailingIcon) ...[
                const SizedBox(width: 12),
                const ShimmerContainer(
                  width: 24,
                  height: 24,
                  borderRadius: BorderRadius.all(Radius.circular(8)),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _TodayScheduleLoadingSkeleton extends StatelessWidget {
  const _TodayScheduleLoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: ShimmerContainer(width: 140, height: 18)),
              SizedBox(width: 16),
              ShimmerContainer(width: 116, height: 18),
            ],
          ),
          SizedBox(height: 12),
          _ScheduleTileLoadingSkeleton(),
        ],
      ),
    );
  }
}

class _ScheduleTileLoadingSkeleton extends StatelessWidget {
  const _ScheduleTileLoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    return BracuCard(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxWidth = constraints.maxWidth;
          return Row(
            children: [
              const ShimmerContainer(
                width: 40,
                height: 40,
                borderRadius: BorderRadius.all(Radius.circular(12)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ShimmerContainer(width: maxWidth * 0.46, height: 14),
                    const SizedBox(height: 6),
                    ShimmerContainer(width: maxWidth * 0.58, height: 11),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _QuickAccessLoadingSkeleton extends StatelessWidget {
  const _QuickAccessLoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Expanded(child: ShimmerContainer(width: 128, height: 20)),
            SizedBox(width: 16),
            ShimmerContainer(width: 68, height: 18),
            SizedBox(width: 14),
            ShimmerContainer(width: 74, height: 18),
          ],
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final layout = quickAccessGridLayout(constraints.maxWidth);
            return Center(
              child: Wrap(
                alignment: WrapAlignment.center,
                runAlignment: WrapAlignment.center,
                spacing: layout.spacing,
                runSpacing: layout.spacing,
                children: List<Widget>.generate(
                  8,
                  (_) =>
                      _QuickAccessItemLoadingSkeleton(width: layout.itemWidth),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _QuickAccessItemLoadingSkeleton extends StatelessWidget {
  const _QuickAccessItemLoadingSkeleton({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) {
    final itemWidth = width - 18;
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.all(9),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const ShimmerContainer(
              width: 38,
              height: 38,
              borderRadius: BorderRadius.all(Radius.circular(12)),
            ),
            const SizedBox(height: 12),
            ShimmerContainer(width: itemWidth * 0.76, height: 14),
            const SizedBox(height: 2),
            ShimmerContainer(width: itemWidth * 0.62, height: 11),
          ],
        ),
      ),
    );
  }
}

class _CampusMapLoadingSkeleton extends StatelessWidget {
  const _CampusMapLoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    return const _ActionBannerLoadingSkeleton(showTrailingIcon: true);
  }
}
