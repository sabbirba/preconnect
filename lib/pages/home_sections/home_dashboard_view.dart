part of 'package:preconnect/pages/home.dart';

extension _HomeDashboardView on _HomeDashboardState {
  Widget _buildHomeDashboardView(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgTop = isDark ? Colors.black : _HomeDashboardState._bgTop;
    final bgBottom = isDark ? Colors.black : _HomeDashboardState._bgBottom;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [bgTop, bgBottom],
        ),
      ),
      child: SafeArea(
        child: Stack(
          children: [
            Positioned(
              top: -80,
              right: -60,
              child: DecorBlob(
                color: _HomeDashboardState._primary.withValues(alpha: 0.12),
                size: 200,
              ),
            ),
            Positioned(
              bottom: -90,
              left: -70,
              child: DecorBlob(
                color: _HomeDashboardState._accent.withValues(alpha: 0.10),
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
                          snapshot.connectionState == ConnectionState.waiting &&
                          data == null;
                      if (isLoading) {
                        return BracuRefreshScroll(
                          onRefresh: _handleRefresh,
                          showScrollTopButton: false,
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
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
                      final cardVisibility =
                          data?.cardVisibility ?? HomeCardPreferences.defaults;
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
                            _TopBar(
                              name: profile['fullName'] ?? 'BRACU Student',
                              photoUrl: photoUrl,
                              onOpenNotifications: () =>
                                  widget.onNavigate(HomeTab.notifications),
                              onProfileTap: () =>
                                  widget.onNavigate(HomeTab.profile),
                            ),
                            if (_captiveStatus?.state ==
                                CaptiveWifiState.captive) ...[
                              const SizedBox(height: 12),
                              _CaptiveWifiBanner(
                                statusCode: _captiveStatus?.httpStatusCode,
                                onOpenLogin: _openWifiLoginAssistant,
                              ),
                            ],
                            const SizedBox(height: 18),
                            StudentOverviewCard(
                              studentId: profile['studentId'] ?? '',
                              shortCode: profile['shortCode'] ?? '',
                              department: profile['departmentName'] ?? '',
                              currentSemester: profile['currentSemester'] ?? '',
                              currentSessionSemesterId:
                                  profile['currentSessionSemesterId'] ?? '',
                              onOpenSupport: () =>
                                  showBracuFundingSupportSheet(context),
                              onOpenSettings: () =>
                                  widget.onNavigate(HomeTab.settings),
                              onLogout: widget.onLogout,
                              countdown:
                                  !cardVisibility.showExamCountdownCard ||
                                      nextCountdown == null
                                  ? null
                                  : InkWell(
                                      borderRadius: BorderRadius.circular(18),
                                      onTap: () =>
                                          widget.onNavigate(nextCountdown.tab),
                                      child: ExamCountdownCard(
                                        title: nextCountdown.title,
                                        targetDateTime:
                                            nextCountdown.targetDateTime,
                                      ),
                                    ),
                            ),
                            if (cardVisibility.showTodaySchedule) ...[
                              const SizedBox(height: 12),
                              InkWell(
                                onTap: () => widget.onNavigate(
                                  (todayExams.isNotEmpty || isExamWeekActive)
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
                                          bottom: 10,
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
                                            color: _HomeDashboardState._accent,
                                            isHighlighted: false,
                                          ),
                                        ),
                                      ),
                                    ),
                              if (todayExams.isNotEmpty &&
                                  visibleEntries.isNotEmpty)
                                const SizedBox(height: 10),
                              if (todayExams.isEmpty &&
                                  (isTodayHoliday || visibleEntries.isEmpty))
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: InkWell(
                                    onTap: () => widget.onNavigate(
                                      isExamWeekActive
                                          ? HomeTab.examSchedule
                                          : HomeTab.studentSchedule,
                                    ),
                                    child: _ScheduleTile(
                                      title: isExamWeekActive
                                          ? 'No Class Today'
                                          : isTodayHoliday
                                          ? 'National Holiday'
                                          : 'No Class Today',
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
                                          bottom: 10,
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
                                            color: _HomeDashboardState._primary,
                                            isHighlighted: false,
                                          ),
                                        ),
                                      ),
                                    ),
                            ],
                            if (cardVisibility.showTodaySchedule &&
                                todayExams.isEmpty &&
                                visibleEntries.isEmpty &&
                                !isTodayHoliday &&
                                !isExamWeekActive)
                              const Padding(
                                padding: EdgeInsets.only(top: 8, bottom: 2),
                                child: _LoadingLine(),
                              ),
                            if (cardVisibility.showRamadanCard && isRamadan)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
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
                                            if (ramadan.sehriEndsAt != null &&
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
                              SizedBox(
                                height:
                                    cardVisibility.showRamadanCard && isRamadan
                                    ? 0
                                    : 10,
                              ),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  const Expanded(
                                    child: _SectionTitle(title: 'Quick Access'),
                                  ),
                                  InkWell(
                                    borderRadius: BorderRadius.circular(8),
                                    onTap: () async {
                                      await InAppReviewPrompt.openStoreListing();
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
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
                                              color: BracuPalette.textPrimary(
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
                                              fontWeight: FontWeight.w600,
                                              color: BracuPalette.textPrimary(
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
                                    borderRadius: BorderRadius.circular(8),
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
                                      padding: const EdgeInsets.symmetric(
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
                                              color: BracuPalette.textPrimary(
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
                                              fontWeight: FontWeight.w600,
                                              color: BracuPalette.textPrimary(
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
                                child: _LoadingLine(),
                              ),
                            BracuActionBannerCard(
                              icon: null,
                              title: 'Campus Map & Contacts',
                              subtitle: 'Location and emergency contacts',
                              iconColor: const Color(0xFF22B573),
                              onTap: _openCampusMapSheet,
                            ),
                            const SizedBox(height: 12),
                            const _InlineBannerAd(),
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

class _InlineBannerAd extends StatefulWidget {
  const _InlineBannerAd();

  @override
  State<_InlineBannerAd> createState() => _InlineBannerAdState();
}

class _InlineBannerAdState extends State<_InlineBannerAd> {
  static const double _placeholderHeight = 50;
  static const MethodChannel _bannerEventsChannel = MethodChannel(
    'preconnect/banner_ad_events',
  );

  double _bannerHeight = _placeholderHeight;

  @override
  void initState() {
    super.initState();
    _bannerEventsChannel.setMethodCallHandler(_handleBannerEvent);
  }

  @override
  void dispose() {
    _bannerEventsChannel.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: AdsPreferences.instance.adsVisible,
      builder: (context, adsVisible, _) {
        if (!adsVisible || !AdsBridge.isSupportedPlatform) {
          return const SizedBox.shrink();
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            final width =
                constraints.maxWidth.isFinite && constraints.maxWidth > 0
                ? constraints.maxWidth
                : MediaQuery.sizeOf(context).width;
            final viewType = defaultTargetPlatform == TargetPlatform.iOS
                ? 'preconnect/banner_ad_ios'
                : 'preconnect/banner_ad_android';

            return SizedBox(
              width: width,
              height: _bannerHeight,
              child: defaultTargetPlatform == TargetPlatform.iOS
                  ? UiKitView(
                      viewType: viewType,
                      creationParams: <String, dynamic>{'width': width},
                      creationParamsCodec: const StandardMessageCodec(),
                      layoutDirection: Directionality.of(context),
                    )
                  : AndroidView(
                      viewType: viewType,
                      creationParams: <String, dynamic>{'width': width},
                      creationParamsCodec: const StandardMessageCodec(),
                      layoutDirection: Directionality.of(context),
                    ),
            );
          },
        );
      },
    );
  }

  Future<dynamic> _handleBannerEvent(MethodCall call) async {
    switch (call.method) {
      case 'bannerSizeChanged':
        final args = call.arguments as Map?;
        final height = (args?['height'] as num?)?.toDouble();
        if (!mounted || height == null || height <= 0) {
          return null;
        }
        setState(() {
          _bannerHeight = height;
        });
        return null;
      default:
        return null;
    }
  }
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: BracuPalette.card(context),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: BracuPalette.textSecondary(
                    context,
                  ).withValues(alpha: 0.18),
                ),
              ),
              alignment: Alignment.center,
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    BracuPalette.primary,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 92,
                    height: 10,
                    decoration: BoxDecoration(
                      color: BracuPalette.card(context),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: 148,
                    height: 18,
                    decoration: BoxDecoration(
                      color: BracuPalette.card(context),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: BracuPalette.card(context),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: BracuPalette.textSecondary(
                    context,
                  ).withValues(alpha: 0.18),
                ),
              ),
              alignment: Alignment.center,
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    BracuPalette.primary,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        StudentOverviewCard(
          studentId: '',
          shortCode: '',
          department: '',
          currentSemester: '',
          currentSessionSemesterId: '',
          onOpenSupport: onOpenSupport,
          onOpenSettings: onOpenSettings,
          onLogout: onLogout,
          countdown: const _LoadingLine(),
        ),
        const SizedBox(height: 12),
        const _LoadingLine(),
        const SizedBox(height: 12),
        const _LoadingLine(),
        const SizedBox(height: 12),
        const _LoadingLine(),
      ],
    );
  }
}

class _LoadingLine extends StatelessWidget {
  const _LoadingLine();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        color: BracuPalette.card(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: BracuPalette.textSecondary(context).withValues(alpha: 0.18),
        ),
      ),
      child: Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2.6,
            valueColor: AlwaysStoppedAnimation<Color>(BracuPalette.primary),
          ),
        ),
      ),
    );
  }
}
