import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/api/auth_service.dart';
import 'package:preconnect/api/profile_service.dart';
import 'package:preconnect/api/progress_service.dart';
import 'package:preconnect/api/schedule_service.dart';
import 'package:preconnect/app.dart';
import 'package:preconnect/pages/class_schedule.dart';
import 'package:preconnect/pages/exam_schedule.dart';
import 'package:preconnect/pages/seat_status.dart';
import 'package:preconnect/pages/degree_progress.dart';
import 'package:preconnect/pages/alarms.dart';
import 'package:preconnect/pages/student_profile.dart';
import 'package:preconnect/pages/share_schedule.dart';
import 'package:preconnect/pages/scan_schedule.dart';
import 'package:preconnect/pages/friend_schedule.dart';
import 'package:preconnect/pages/devs.dart';
import 'package:preconnect/pages/settings.dart';
import 'package:preconnect/pages/home_tab.dart';
import 'package:preconnect/pages/home_sections/exam_countdown.dart';
import 'package:preconnect/pages/home_sections/student_overview.dart';
import 'package:preconnect/pages/shared_widgets/section_badge.dart';
import 'package:preconnect/model/section_info.dart' as section;
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/cached_image.dart';
import 'package:preconnect/tools/home_card_preferences.dart';
import 'package:preconnect/tools/holiday_status.dart';
import 'package:preconnect/tools/in_app_review_prompt.dart';
import 'package:preconnect/tools/ramadan_timing.dart';
import 'package:preconnect/tools/refresh_bus.dart';
import 'package:preconnect/tools/refresh_guard.dart';
import 'package:preconnect/tools/time_utils.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  static final StreamController<HomeTab> _shortcutTabController =
      StreamController<HomeTab>.broadcast();
  static HomeTab? _pendingShortcutTab;

  static void requestShortcutTab(HomeTab tab) {
    _pendingShortcutTab = tab;
    _shortcutTabController.add(tab);
  }

  static HomeTab? takePendingShortcutTab() {
    final pending = _pendingShortcutTab;
    _pendingShortcutTab = null;
    return pending;
  }

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  HomeTab selectedTab = HomeTab.settings;
  StreamSubscription<HomeTab>? _shortcutTabSubscription;

  late final Map<HomeTab, WidgetBuilder> pages = {
    HomeTab.settings: (_) => const SettingsPage(),
    HomeTab.dashboard: (_) => _HomeDashboard(
      onNavigate: _setTab,
      onLogout: () => _confirmLogout(context),
    ),
    HomeTab.profile: (_) => const StudentProfile(),
    HomeTab.studentSchedule: (_) => const ClassSchedule(),
    HomeTab.examSchedule: (_) => const ExamSchedule(),
    HomeTab.seatStatus: (_) => const SeatStatusPage(),
    HomeTab.degreeProgress: (_) => const DegreeProgressPage(),
    HomeTab.alarms: (_) => const AlarmPage(),
    HomeTab.shareSchedule: (_) => const ShareSchedulePage(),
    HomeTab.scanSchedule: (_) => const ScanSchedulePage(),
    HomeTab.friendSchedule: (_) => FriendSchedulePage(onNavigate: _setTab),
    HomeTab.devs: (_) => const DevsPage(),
  };
  late final List<HomeTab> _tabOrder = HomeTab.values;
  final Set<HomeTab> _builtTabs = {HomeTab.settings};

  @override
  void initState() {
    super.initState();
    final pendingShortcutTab = HomePage.takePendingShortcutTab();
    if (pendingShortcutTab != null) {
      selectedTab = pendingShortcutTab;
      _builtTabs.add(pendingShortcutTab);
    }
    HomeTabRegistry.setActive(selectedTab);
    _shortcutTabSubscription = HomePage._shortcutTabController.stream.listen((
      tab,
    ) {
      if (!mounted) return;
      _setTab(tab);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || selectedTab != HomeTab.settings) return;
      _setTab(HomeTab.dashboard);
    });
  }

  @override
  void dispose() {
    _shortcutTabSubscription?.cancel();
    super.dispose();
  }

  void _setTab(HomeTab tab) {
    final shouldJumpClass = tab == HomeTab.studentSchedule;
    final shouldJumpExam = tab == HomeTab.examSchedule;
    setState(() {
      selectedTab = tab;
    });
    HomeTabRegistry.setActive(tab);
    if (shouldJumpClass || shouldJumpExam) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || selectedTab != tab) return;
        if (shouldJumpClass) {
          ClassSchedule.requestJump();
        } else if (shouldJumpExam) {
          ExamSchedule.requestJump();
        }
      });
    }
  }

  void _handleBack() {
    if (selectedTab == HomeTab.dashboard) return;
    if (selectedTab == HomeTab.scanSchedule ||
        selectedTab == HomeTab.shareSchedule) {
      _setTab(HomeTab.friendSchedule);
    } else {
      _setTab(HomeTab.dashboard);
    }
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.25),
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: BracuPalette.card(context),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.logout, color: BracuPalette.primary),
                    const SizedBox(width: 8),
                    Text(
                      'Confirm Sign Out?',
                      style: TextStyle(
                        color: BracuPalette.textPrimary(context),
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'Sign out will clear cached data. You can sign in again for fresh data.',
                  style: TextStyle(
                    color: BracuPalette.textSecondary(context),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: BracuPalette.primary,
                          side: BorderSide(
                            color: BracuPalette.primary.withValues(alpha: 0.6),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: BracuPalette.primary,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text('Sign Out'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (shouldLogout == true) {
      if (!context.mounted) return;
      await AuthService().logout();
      RefreshBus.instance.notify(reason: 'auth');
      if (!context.mounted) return;
      Navigator.pushReplacementNamed(context, '/onboarding');
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: selectedTab == HomeTab.dashboard,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && selectedTab != HomeTab.dashboard) {
          if (selectedTab == HomeTab.scanSchedule ||
              selectedTab == HomeTab.shareSchedule) {
            _setTab(HomeTab.friendSchedule);
          } else {
            _setTab(HomeTab.dashboard);
          }
        }
      },
      child: Scaffold(
        body: BracuBackScope(
          canGoBack: selectedTab != HomeTab.dashboard,
          onBack: _handleBack,
          child: IndexedStack(
            index: selectedTab.index,
            children: _tabOrder.map((tab) {
              if (tab == selectedTab || _builtTabs.contains(tab)) {
                _builtTabs.add(tab);
                return pages[tab]!(context);
              }
              return const SizedBox.shrink();
            }).toList(),
          ),
        ),
      ),
    );
  }
}

class _HomeDashboard extends StatefulWidget {
  const _HomeDashboard({required this.onNavigate, required this.onLogout});

  final void Function(HomeTab tab) onNavigate;
  final Future<void> Function() onLogout;

  @override
  State<_HomeDashboard> createState() => _HomeDashboardState();
}

class _HomeDashboardState extends State<_HomeDashboard> {
  static const _bgTop = Color(0xFFEAF4FF);
  static const _bgBottom = Color(0xFFF3FFF4);
  static const _primary = Color(0xFF1E6BE3);
  static const _accent = Color(0xFF22B573);

  late Future<_HomeData> _future;
  _HomeData? _latestData;
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _future = _loadData().then((data) {
      _latestData = data;
      return data;
    });
    unawaited(_preloadDegreeProgress());
    RefreshBus.instance.addListener(_onRefreshSignal);
  }

  @override
  void dispose() {
    RefreshBus.instance.removeListener(_onRefreshSignal);
    super.dispose();
  }

  void _onRefreshSignal() {
    if (!mounted) return;
    if (RefreshBus.instance.isReason('home_dashboard')) {
      return;
    }
    if (RefreshBus.instance.isReason('home_card_settings_changed')) {
      setState(() {
        _future = _loadData().then((data) {
          _latestData = data;
          return data;
        });
      });
      return;
    }
    if (RefreshBus.instance.isReason('auth')) {
      unawaited(_handleRefresh(notify: false));
    }
  }

  Future<_HomeData> _loadData({bool forceRefresh = false}) async {
    final profileFuture = forceRefresh
        ? ProfileService().fetchProfile()
        : ProfileService().getProfile();
    final scheduleFuture = forceRefresh
        ? ScheduleService().fetchStudentSchedule()
        : ScheduleService().getStudentSchedule();
    final ramadanFuture = RamadanTiming.getRamadanStatus(
      forceRefresh: forceRefresh,
    );
    final holidayFuture = HolidayTiming.getTodayStatus(
      forceRefresh: forceRefresh,
    );
    final cardVisibilityFuture = HomeCardPreferences.load();

    final results = await Future.wait<dynamic>([
      profileFuture,
      scheduleFuture,
      ramadanFuture,
      holidayFuture,
      cardVisibilityFuture,
    ]);

    Map<String, String?>? profile = results[0] as Map<String, String?>?;
    String? scheduleJson = results[1] as String?;
    final ramadan = results[2] as RamadanStatus;
    final isRamadan = ramadan.isRamadan;
    final holidayStatus = results[3] as HolidayStatus;
    final cardVisibility = results[4] as HomeCardVisibility;

    if (!forceRefresh) {
      profile ??= await ProfileService().fetchProfile();
      scheduleJson ??= await ScheduleService().fetchStudentSchedule();
    }

    final photoUrl = ApiConfig.photoUrl(profile?['photoFilePath']);
    final List<_ScheduleEntry> entries = [];
    final List<section.Section> sections = [];
    if (scheduleJson != null && scheduleJson.trim().isNotEmpty) {
      final decoded = (jsonDecode(scheduleJson) as List<dynamic>)
          .map((e) => section.Section.fromJson(e))
          .toList();
      sections.addAll(decoded);
      for (final section in decoded) {
        for (final s in section.sectionSchedule.classSchedules) {
          final adjusted = RamadanTiming.adjustRange(
            s.startTime,
            s.endTime,
            isRamadan: isRamadan,
          );
          entries.add(
            _ScheduleEntry(
              day: s.day,
              startTime: adjusted.startTime,
              endTime: adjusted.endTime,
              courseCode: section.courseCode,
              sectionName: section.sectionName,
              roomNumber: section.roomNumber,
              faculties: section.faculties,
            ),
          );
        }
      }
    }
    return _HomeData(
      profile: profile,
      entries: entries,
      photoUrl: photoUrl,
      sections: sections,
      isRamadan: isRamadan,
      ramadan: ramadan,
      holiday: holidayStatus,
      cardVisibility: cardVisibility,
    );
  }

  Future<void> _preloadDegreeProgress({bool forceRefresh = false}) async {
    if (forceRefresh) {
      await ProgressService().fetchProgress();
      return;
    }
    await ProgressService().getProgress();
  }

  Future<void> _handleRefresh({bool notify = true}) async {
    if (_isRefreshing) return;
    if (!await ensureOnline(context, notify: notify)) {
      return;
    }
    _isRefreshing = true;
    unawaited(_preloadDegreeProgress(forceRefresh: true));
    try {
      final fresh = await _loadData(forceRefresh: true);
      if (!mounted) return;
      setState(() {
        _latestData = fresh;
      });
      if (notify) {
        RefreshBus.instance.notify(reason: 'home_dashboard');
      }
    } finally {
      _isRefreshing = false;
    }
  }

  String _todayName() {
    switch (DateTime.now().weekday) {
      case DateTime.monday:
        return 'Monday';
      case DateTime.tuesday:
        return 'Tuesday';
      case DateTime.wednesday:
        return 'Wednesday';
      case DateTime.thursday:
        return 'Thursday';
      case DateTime.friday:
        return 'Friday';
      case DateTime.saturday:
        return 'Saturday';
      case DateTime.sunday:
        return 'Sunday';
      default:
        return 'Monday';
    }
  }

  _ExamCountdownData? _nextExamCountdown(List<section.Section> sections) {
    final now = DateTime.now();
    final exams = <_ExamCountdownData>[];
    for (final s in sections) {
      final schedule = s.sectionSchedule;
      final mid = BracuTime.parseDateTime(
        schedule.midExamDate,
        schedule.midExamStartTime,
      );
      if (mid != null) {
        exams.add(
          _ExamCountdownData(time: mid, courseCode: s.courseCode, type: 'Mid'),
        );
      }
      final fin = BracuTime.parseDateTime(
        schedule.finalExamDate,
        schedule.finalExamStartTime,
      );
      if (fin != null) {
        exams.add(
          _ExamCountdownData(
            time: fin,
            courseCode: s.courseCode,
            type: 'Final',
          ),
        );
      }
    }
    final upcoming = exams.where((e) => !e.time.isBefore(now)).toList()
      ..sort((a, b) => a.time.compareTo(b.time));
    if (upcoming.isEmpty) return null;
    return upcoming.first;
  }

  int _timeToMinutes(String time) {
    return BracuTime.toMinutes(time) ?? 0;
  }

  _ScheduleEntry? _pickNextEntry(List<_ScheduleEntry> entries, int nowMinutes) {
    for (final entry in entries) {
      final start = _timeToMinutes(entry.startTime);
      final end = _timeToMinutes(entry.endTime);
      if (nowMinutes >= start && nowMinutes < end) {
        return entry;
      }
    }
    for (final entry in entries) {
      final start = _timeToMinutes(entry.startTime);
      if (start >= nowMinutes) {
        return entry;
      }
    }
    return null;
  }

  String? _nextRamadanTarget({String? sehri, String? iftar}) {
    DateTime? nextOccurrence(String? time) {
      final parsed = BracuTime.parseTime(time);
      if (parsed == null) return null;
      final now = DateTime.now();
      var target = DateTime(
        now.year,
        now.month,
        now.day,
        parsed.hour,
        parsed.minute,
      );
      if (!target.isAfter(now)) {
        target = target.add(const Duration(days: 1));
      }
      return target;
    }

    final sehriAt = nextOccurrence(sehri);
    final iftarAt = nextOccurrence(iftar);
    if (sehriAt == null && iftarAt == null) return null;
    if (sehriAt == null) return 'Iftar';
    if (iftarAt == null) return 'Sehri';
    return sehriAt.isBefore(iftarAt) ? 'Sehri' : 'Iftar';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgTop = isDark ? Colors.black : _bgTop;
    final bgBottom = isDark ? Colors.black : _bgBottom;
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
              child: _DecorBlob(
                color: _primary.withValues(alpha: 0.12),
                size: 200,
              ),
            ),
            Positioned(
              bottom: -90,
              left: -70,
              child: _DecorBlob(
                color: _accent.withValues(alpha: 0.10),
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
                      final profile = data?.profile ?? {};
                      final photoUrl = data?.photoUrl;
                      final ramadan =
                          data?.ramadan ??
                          const RamadanStatus(isRamadan: false);
                      final isRamadan = ramadan.isRamadan;
                      final nextCountdownTarget = _nextRamadanTarget(
                        sehri: ramadan.sehriEndsAt,
                        iftar: ramadan.iftarAt,
                      );
                      final orderedPrayerKeys = const [
                        'Fajr',
                        'Dhuhr',
                        'Asr',
                        'Maghrib',
                        'Isha',
                      ];
                      final prayerEntries = <(String, String)>[];
                      for (final key in orderedPrayerKeys) {
                        final value = ramadan.prayerTimes[key];
                        if (value == null || value.trim().isEmpty) continue;
                        prayerEntries.add((key, value));
                      }
                      for (final entry in ramadan.prayerTimes.entries) {
                        if (orderedPrayerKeys.contains(entry.key)) continue;
                        if (entry.value.trim().isEmpty) continue;
                        prayerEntries.add((entry.key, entry.value));
                      }
                      final holidayStatus =
                          data?.holiday ?? HolidayStatus.empty;
                      final cardVisibility =
                          data?.cardVisibility ?? HomeCardPreferences.defaults;
                      final isTodayHoliday = holidayStatus.isTodayHoliday;
                      final today = _todayName();
                      final todayDate = DateFormat(
                        'd MMMM, y',
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
                      final visibleEntries = isTodayHoliday
                          ? <_ScheduleEntry>[]
                          : todayEntries;
                      final nowMinutes = _timeToMinutes(
                        '${DateTime.now().hour}:${DateTime.now().minute}',
                      );
                      _ScheduleEntry? nextEntry;
                      if (visibleEntries.isNotEmpty) {
                        nextEntry = _pickNextEntry(visibleEntries, nowMinutes);
                      }
                      final nextExam = _nextExamCountdown(
                        data?.sections ?? const <section.Section>[],
                      );
                      return BracuRefreshScroll(
                        onRefresh: _handleRefresh,
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _TopBar(
                              name: profile['fullName'] ?? 'BRACU Student',
                              photoUrl: photoUrl,
                              onProfileTap: () =>
                                  widget.onNavigate(HomeTab.profile),
                            ),
                            const SizedBox(height: 18),
                            StudentOverviewCard(
                              studentId: profile['studentId'] ?? '',
                              shortCode: profile['shortCode'] ?? '',
                              phoneNumber: profile['mobileNo'] ?? '',
                              department: profile['departmentName'] ?? '',
                              currentSemester: profile['currentSemester'] ?? '',
                              currentSessionSemesterId:
                                  profile['currentSessionSemesterId'] ?? '',
                              onOpenSettings: () =>
                                  widget.onNavigate(HomeTab.settings),
                              onLogout: widget.onLogout,
                              showStudentContactCards:
                                  cardVisibility.showStudentContactCards,
                              countdown:
                                  !cardVisibility.showExamCountdownCard ||
                                      nextExam == null
                                  ? null
                                  : InkWell(
                                      borderRadius: BorderRadius.circular(18),
                                      onTap: () => widget.onNavigate(
                                        HomeTab.examSchedule,
                                      ),
                                      child: ExamCountdownCard(
                                        title:
                                            nextExam.time
                                                    .difference(DateTime.now())
                                                    .inDays <=
                                                3
                                            ? '${nextExam.courseCode} ${nextExam.type} Exam'
                                            : '${nextExam.type} Exam',
                                        targetDateTime: nextExam.time,
                                        daysOnly: cardVisibility
                                            .showExamCountdownDaysOnly,
                                      ),
                                    ),
                            ),
                            if (cardVisibility.showTodaySchedule) ...[
                              const SizedBox(height: 12),
                              InkWell(
                                onTap: () =>
                                    widget.onNavigate(HomeTab.studentSchedule),
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
                              if (isTodayHoliday || visibleEntries.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: InkWell(
                                    onTap: () => widget.onNavigate(
                                      HomeTab.studentSchedule,
                                    ),
                                    child: _ScheduleTile(
                                      title: isTodayHoliday
                                          ? 'National Holiday'
                                          : 'No Class Today',
                                      subtitle: isTodayHoliday
                                          ? holidayStatus.displayNames
                                          : 'Enjoy your day off or check your schedule.',
                                      badge: isTodayHoliday ? 'OFF' : '--',
                                      color: _primary,
                                    ),
                                  ),
                                )
                              else
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
                                            color: _primary,
                                            isHighlighted: entry == nextEntry,
                                          ),
                                        ),
                                      ),
                                    ),
                            ],
                            if (cardVisibility.showRamadanCard && isRamadan)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 16),
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
                                        const SizedBox(height: 12),
                                      ],
                                      if (prayerEntries.isNotEmpty)
                                        Column(
                                          children: [
                                            for (
                                              var i = 0;
                                              i < prayerEntries.length;
                                              i++
                                            ) ...[
                                              _RamadanTimeRow(
                                                label: prayerEntries[i].$1,
                                                value: BracuTime.format(
                                                  prayerEntries[i].$2,
                                                ),
                                              ),
                                              if (i != prayerEntries.length - 1)
                                                Divider(
                                                  height: 10,
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
                                          ],
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            if (cardVisibility.showQuickAccessSection) ...[
                              const SizedBox(height: 10),
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
                                          text:
                                              'https://play.google.com/store/apps/details?id=com.sabbirba.preconnect',
                                          subject:
                                              'PreConnect.app • Prepare. Connect. Succeed.',
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
                                  const spacing = 12.0;
                                  final width =
                                      (constraints.maxWidth - spacing * 2) / 3;
                                  return Wrap(
                                    spacing: spacing,
                                    runSpacing: spacing,
                                    children: [
                                      _QuickActionCard(
                                        width: width,
                                        icon: Icons.person_outline,
                                        title: 'Profile',
                                        subtitle: 'Info & ID',
                                        color: _primary,
                                        onTap: () =>
                                            widget.onNavigate(HomeTab.profile),
                                      ),
                                      _QuickActionCard(
                                        width: width,
                                        icon: Icons.schedule_outlined,
                                        title: 'Classes',
                                        subtitle: 'Schedules',
                                        color: _accent,
                                        onTap: () => widget.onNavigate(
                                          HomeTab.studentSchedule,
                                        ),
                                      ),
                                      _QuickActionCard(
                                        width: width,
                                        icon: Icons.alarm_outlined,
                                        title: 'Alarms',
                                        subtitle: 'Reminders',
                                        color: const Color(0xFFFF8A34),
                                        onTap: () =>
                                            widget.onNavigate(HomeTab.alarms),
                                      ),
                                      _QuickActionCard(
                                        width: width,
                                        icon: Icons.event_note_outlined,
                                        title: 'Exams',
                                        subtitle: 'Dates',
                                        color: const Color(0xFF7C56FF),
                                        onTap: () => widget.onNavigate(
                                          HomeTab.examSchedule,
                                        ),
                                      ),
                                      _QuickActionCard(
                                        width: width,
                                        icon: Icons.school_outlined,
                                        title: 'Degree',
                                        subtitle: 'Progress',
                                        color: const Color(0xFF2C9DFF),
                                        onTap: () => widget.onNavigate(
                                          HomeTab.degreeProgress,
                                        ),
                                      ),
                                      _QuickActionCard(
                                        width: width,
                                        icon: Icons.people_outline,
                                        title: 'Friends',
                                        subtitle: 'Schedules',
                                        color: const Color(0xFF5B8DEF),
                                        onTap: () => widget.onNavigate(
                                          HomeTab.friendSchedule,
                                        ),
                                      ),
                                      _QuickActionCard(
                                        width: width,
                                        icon: Icons.insights_outlined,
                                        title: 'Seats',
                                        subtitle: 'Live Sections',
                                        color: const Color(0xFF00A8E8),
                                        onTap: () => widget.onNavigate(
                                          HomeTab.seatStatus,
                                        ),
                                      ),
                                      _QuickActionCard(
                                        width: width,
                                        icon: Icons.developer_mode_outlined,
                                        title: 'Devs',
                                        subtitle: 'About Us',
                                        color: const Color(0xFF2C9DFF),
                                        onTap: () =>
                                            widget.onNavigate(HomeTab.devs),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ],
                            const SizedBox(height: 12),
                            _OpenWebCard(
                              onTap: () => _openPreconnectWeb(
                                context,
                                'https://preconnect.app',
                              ),
                            ),
                            const SizedBox(height: 12),
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
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.name,
    required this.photoUrl,
    required this.onProfileTap,
  });

  final String name;
  final String? photoUrl;
  final VoidCallback onProfileTap;

  @override
  Widget build(BuildContext context) {
    final initial = name.isNotEmpty ? name.trim().characters.first : 'S';
    final textSecondary = BracuPalette.textSecondary(context);
    final textPrimary = BracuPalette.textPrimary(context);
    return Row(
      children: [
        Expanded(
          child: InkWell(
            onTap: onProfileTap,
            borderRadius: BorderRadius.circular(14),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E6BE3),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  alignment: Alignment.center,
                  child: photoUrl == null
                      ? Text(
                          initial.toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        )
                      : ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: CachedImage(
                            url: photoUrl!,
                            fit: BoxFit.cover,
                            width: 42,
                            height: 42,
                            filterQuality: FilterQuality.low,
                            placeholder: Center(
                              child: Text(
                                initial.toUpperCase(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            error: Center(
                              child: Text(
                                initial.toUpperCase(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Welcome Back',
                      style: TextStyle(fontSize: 12, color: textSecondary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      name,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: textPrimary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        ValueListenableBuilder<ThemeMode>(
          valueListenable: ThemeController.of(context),
          builder: (context, mode, _) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            return IconButton(
              tooltip: isDark ? 'Light mode' : 'Dark mode',
              onPressed: () => ThemeController.setTheme(
                context,
                isDark ? ThemeMode.light : ThemeMode.dark,
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              visualDensity: VisualDensity.compact,
              icon: Icon(
                isDark ? Icons.wb_sunny_outlined : Icons.dark_mode_outlined,
                color: BracuPalette.primary,
              ),
            );
          },
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: BracuPalette.textPrimary(context),
      ),
    );
  }
}

class _OpenWebCard extends StatelessWidget {
  const _OpenWebCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: BracuPalette.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: BracuPalette.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.open_in_new,
                  color: BracuPalette.primary,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Open PreConnect Web',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: BracuPalette.textPrimary(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'PreConnect.app • Prepare. Connect. Succeed.',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: BracuPalette.textSecondary(context),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: BracuPalette.textSecondary(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _openPreconnectWeb(BuildContext context, String url) async {
  final uri = Uri.parse(url);
  final mode = kIsWeb
      ? LaunchMode.platformDefault
      : LaunchMode.inAppBrowserView;
  var launched = await launchUrl(uri, mode: mode);
  if (!launched && !kIsWeb) {
    launched = await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
  }
  if (!launched && context.mounted) {
    showAppSnackBar(context, 'Unable to open browser.');
  }
}

class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({
    required this.width,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final double width;
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textSecondary = BracuPalette.textSecondary(context);
    final textPrimary = BracuPalette.textPrimary(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: width,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: BracuPalette.card(context),
          borderRadius: BorderRadius.circular(18),
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(fontSize: 11, color: textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScheduleTile extends StatelessWidget {
  const _ScheduleTile({
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.color,
    this.trailing,
    this.trailingSub,
    this.isHighlighted = false,
  });

  final String title;
  final String subtitle;
  final String badge;
  final Color color;
  final String? trailing;
  final String? trailingSub;
  final bool isHighlighted;

  @override
  Widget build(BuildContext context) {
    final textSecondary = BracuPalette.textSecondary(context);
    final textPrimary = BracuPalette.textPrimary(context);
    return BracuCard(
      isHighlighted: isHighlighted,
      highlightColor: BracuPalette.primary,
      child: Row(
        children: [
          SectionBadge(label: badge, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                    color: textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  trailing!,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: textPrimary,
                  ),
                ),
                if (trailingSub != null && trailingSub!.trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    trailingSub!,
                    style: TextStyle(fontSize: 11, color: textSecondary),
                  ),
                ],
              ],
            ),
        ],
      ),
    );
  }
}

class _RamadanTimeRow extends StatelessWidget {
  const _RamadanTimeRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: BracuPalette.textPrimary(context),
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: BracuPalette.textSecondary(context),
          ),
        ),
      ],
    );
  }
}

class _RamadanHeroTime extends StatelessWidget {
  const _RamadanHeroTime({
    required this.label,
    required this.value,
    this.alignRight = false,
  });

  final String label;
  final String value;
  final bool alignRight;

  @override
  Widget build(BuildContext context) {
    final icon = label.toLowerCase() == 'sehri'
        ? Icons.nightlight_round
        : Icons.wb_sunny_outlined;
    return Column(
      crossAxisAlignment: alignRight
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: BracuPalette.textSecondary(context)),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: BracuPalette.textSecondary(context),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          value,
          textAlign: alignRight ? TextAlign.right : TextAlign.left,
          style: TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w800,
            color: BracuPalette.textPrimary(context),
            height: 1.0,
          ),
        ),
      ],
    );
  }
}

class _RamadanTopCountdown extends StatelessWidget {
  const _RamadanTopCountdown({
    required this.ramadanDay,
    required this.targetLabel,
    required this.targetTime,
  });

  final int? ramadanDay;
  final String targetLabel;
  final String? targetTime;

  @override
  Widget build(BuildContext context) {
    if (targetTime == null || targetTime!.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    return SizedBox(
      width: double.infinity,
      child: StreamBuilder<int>(
        stream: Stream<int>.periodic(
          const Duration(seconds: 1),
          (tick) => tick,
        ),
        builder: (context, snapshot) {
          final now = DateTime.now();
          final remaining = _durationTo(targetTime!, now);
          if (remaining == null) return const SizedBox.shrink();
          return Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$targetLabel • ${BracuTime.format(targetTime)}',
                      style: TextStyle(
                        color: BracuPalette.textSecondary(context),
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      ramadanDay == null
                          ? 'Ramadan'
                          : 'Ramadan Day $ramadanDay',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: BracuPalette.textPrimary(context),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _RamadanCountdownDigital(remaining: remaining),
            ],
          );
        },
      ),
    );
  }

  Duration? _durationTo(String targetTime, DateTime now) {
    final parsed = BracuTime.parseTime(targetTime);
    if (parsed == null) return null;
    var target = DateTime(
      now.year,
      now.month,
      now.day,
      parsed.hour,
      parsed.minute,
    );
    if (!target.isAfter(now)) {
      target = target.add(const Duration(days: 1));
    }
    return target.difference(now);
  }
}

class _RamadanCountdownDigital extends StatelessWidget {
  const _RamadanCountdownDigital({required this.remaining});

  final Duration remaining;

  @override
  Widget build(BuildContext context) {
    final totalSeconds = remaining.inSeconds;
    final safeSeconds = totalSeconds < 0 ? 0 : totalSeconds;
    final hours = safeSeconds ~/ 3600;
    final minutes = (safeSeconds ~/ 60) % 60;
    final seconds = safeSeconds % 60;

    Widget cell(String value, String label) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: TextStyle(
              color: BracuPalette.textPrimary(context),
              fontWeight: FontWeight.w700,
              fontSize: 14,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: BracuPalette.textSecondary(context),
              fontWeight: FontWeight.w600,
              fontSize: 10,
            ),
          ),
        ],
      );
    }

    final units = <({String value, String label})>[];
    if (hours > 0) {
      units.add((value: hours.toString().padLeft(2, '0'), label: 'Hours'));
    }
    if (minutes > 0) {
      units.add((value: minutes.toString().padLeft(2, '0'), label: 'Minutes'));
    }
    units.add((value: seconds.toString().padLeft(2, '0'), label: 'Seconds'));

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < units.length; i++) ...[
          cell(units[i].value, units[i].label),
          if (i != units.length - 1) const SizedBox(width: 8),
        ],
      ],
    );
  }
}

class _DecorBlob extends StatelessWidget {
  const _DecorBlob({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(size / 2),
      ),
    );
  }
}

class _HomeData {
  _HomeData({
    required this.profile,
    required this.entries,
    required this.photoUrl,
    required this.sections,
    required this.isRamadan,
    required this.ramadan,
    required this.holiday,
    required this.cardVisibility,
  });

  final Map<String, String?>? profile;
  final List<_ScheduleEntry> entries;
  final String? photoUrl;
  final List<section.Section> sections;
  final bool isRamadan;
  final RamadanStatus ramadan;
  final HolidayStatus holiday;
  final HomeCardVisibility cardVisibility;
}

class _ScheduleEntry {
  _ScheduleEntry({
    required this.day,
    required this.startTime,
    required this.endTime,
    required this.courseCode,
    required this.sectionName,
    required this.roomNumber,
    required this.faculties,
  });

  final String day;
  final String startTime;
  final String endTime;
  final String courseCode;
  final String sectionName;
  final String roomNumber;
  final String faculties;
}

class _ExamCountdownData {
  _ExamCountdownData({
    required this.time,
    required this.courseCode,
    required this.type,
  });

  final DateTime time;
  final String courseCode;
  final String type;
}
