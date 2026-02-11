import 'dart:async';
import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:preconnect/api/bracu_auth_manager.dart';
import 'package:preconnect/app.dart';
import 'package:preconnect/pages/class_schedule.dart';
import 'package:preconnect/pages/exam_schedule.dart';
import 'package:preconnect/pages/alarms.dart';
import 'package:preconnect/pages/student_profile.dart';
import 'package:preconnect/pages/share_schedule.dart';
import 'package:preconnect/pages/scan_schedule.dart';
import 'package:preconnect/pages/friend_schedule.dart';
import 'package:preconnect/pages/notifications.dart';
import 'package:preconnect/pages/devs.dart';
import 'package:preconnect/pages/home_tab.dart';
import 'package:preconnect/pages/home_sections/exam_countdown.dart';
import 'package:preconnect/pages/home_sections/student_overview.dart';
import 'package:preconnect/pages/shared_widgets/section_badge.dart';
import 'package:preconnect/model/section_info.dart' as section;
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/notification_scheduler.dart';
import 'package:preconnect/tools/refresh_bus.dart';
import 'package:preconnect/tools/refresh_guard.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  HomeTab selectedTab = HomeTab.dashboard;

  late final Map<HomeTab, WidgetBuilder> pages = {
    HomeTab.dashboard: (_) => _HomeDashboard(
      onNavigate: _setTab,
      onLogout: () => _confirmLogout(context),
    ),
    HomeTab.notifications: (_) => const NotificationPage(),
    HomeTab.profile: (_) => const StudentProfile(),
    HomeTab.studentSchedule: (_) => const ClassSchedule(),
    HomeTab.examSchedule: (_) => const ExamSchedule(),
    HomeTab.alarms: (_) => const AlarmPage(),
    HomeTab.shareSchedule: (_) => const ShareSchedulePage(),
    HomeTab.scanSchedule: (_) => const ScanSchedulePage(),
    HomeTab.friendSchedule: (_) => FriendSchedulePage(onNavigate: _setTab),
    HomeTab.devs: (_) => const DevsPage(),
  };
  late final List<HomeTab> _tabOrder = HomeTab.values;
  final Set<HomeTab> _builtTabs = {HomeTab.dashboard};

  void _setTab(HomeTab tab) {
    if (tab == HomeTab.studentSchedule) {
      ClassSchedule.requestJump();
    } else if (tab == HomeTab.examSchedule) {
      ExamSchedule.requestJump();
    }
    setState(() {
      selectedTab = tab;
    });
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
      await BracuAuthManager().logout();
      RefreshBus.instance.notify(reason: 'auth');
      if (!context.mounted) return;
      Navigator.pushReplacementNamed(context, '/login');
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

  @override
  void initState() {
    super.initState();
    _future = _loadData();
    unawaited(NotificationScheduler.syncSchedules());
    RefreshBus.instance.addListener(_onRefreshSignal);
  }

  @override
  void dispose() {
    RefreshBus.instance.removeListener(_onRefreshSignal);
    super.dispose();
  }

  void _onRefreshSignal() {
    if (!mounted) return;
    if (RefreshBus.instance.reason == 'home_dashboard') {
      return;
    }
    unawaited(_handleRefresh(notify: false));
  }

  Future<_HomeData> _loadData({bool forceRefresh = false}) async {
    final profileFuture = forceRefresh
        ? BracuAuthManager().fetchProfile()
        : BracuAuthManager().getProfile();
    final scheduleFuture = forceRefresh
        ? BracuAuthManager().fetchStudentSchedule()
        : BracuAuthManager().getStudentSchedule();

    final results = await Future.wait<dynamic>([profileFuture, scheduleFuture]);

    Map<String, String?>? profile = results[0] as Map<String, String?>?;
    String? scheduleJson = results[1] as String?;

    if (!forceRefresh) {
      profile ??= await BracuAuthManager().fetchProfile();
      scheduleJson ??= await BracuAuthManager().fetchStudentSchedule();
    }

    final photoUrl = _buildPhotoUrl(profile?['photoFilePath']);
    final List<_ScheduleEntry> entries = [];
    final List<section.Section> sections = [];
    if (scheduleJson != null && scheduleJson.trim().isNotEmpty) {
      final decoded = (jsonDecode(scheduleJson) as List<dynamic>)
          .map((e) => section.Section.fromJson(e))
          .toList();
      sections.addAll(decoded);
      for (final section in decoded) {
        for (final s in section.sectionSchedule.classSchedules) {
          entries.add(
            _ScheduleEntry(
              day: s.day,
              startTime: s.startTime,
              endTime: s.endTime,
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
    );
  }

  Future<void> _handleRefresh({bool notify = true}) async {
    if (!await ensureOnline(context, notify: notify)) {
      return;
    }
    setState(() {
      _future = _loadData(forceRefresh: true);
    });
    await _future;
    if (notify) {
      RefreshBus.instance.notify(reason: 'home_dashboard');
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

  DateTime? _parseExamDateTime(String? date, String? time) {
    if (date == null || date.trim().isEmpty) return null;
    final rawDate = date.trim();
    final dateFormats = <DateFormat>[
      DateFormat('yyyy-MM-dd'),
      DateFormat('yyyy/MM/dd'),
      DateFormat('yyyy.MM.dd'),
      DateFormat('dd-MM-yyyy'),
      DateFormat('dd/MM/yyyy'),
      DateFormat('d/M/yyyy'),
      DateFormat('d MMM yyyy'),
      DateFormat('d MMM, yyyy'),
      DateFormat('d-MMM-yyyy'),
      DateFormat('MMM d, yyyy'),
    ];

    DateTime? datePart;
    for (final f in dateFormats) {
      try {
        datePart = f.parseStrict(rawDate);
        break;
      } catch (_) {}
    }
    datePart ??= DateTime.tryParse(rawDate);
    if (datePart == null) return null;

    if (time == null || time.trim().isEmpty) {
      return DateTime(datePart.year, datePart.month, datePart.day);
    }

    final rawTime = time.trim().toUpperCase();
    final timeFormats = <DateFormat>[
      DateFormat('HH:mm'),
      DateFormat('H:mm'),
      DateFormat('HH:mm:ss'),
      DateFormat('H:mm:ss'),
      DateFormat('hh:mm a'),
      DateFormat('h:mm a'),
      DateFormat('hh:mm:ss a'),
      DateFormat('h:mm:ss a'),
    ];
    DateTime? timePart;
    for (final f in timeFormats) {
      try {
        timePart = f.parseStrict(rawTime);
        break;
      } catch (_) {}
    }
    timePart ??= DateTime.tryParse(rawTime);

    if (timePart == null) {
      return DateTime(datePart.year, datePart.month, datePart.day);
    }
    return DateTime(
      datePart.year,
      datePart.month,
      datePart.day,
      timePart.hour,
      timePart.minute,
    );
  }

  _ExamCountdownData? _nextExamCountdown(List<section.Section> sections) {
    final now = DateTime.now();
    final exams = <_ExamCountdownData>[];
    for (final s in sections) {
      final schedule = s.sectionSchedule;
      final mid = _parseExamDateTime(
        schedule.midExamDate,
        schedule.midExamStartTime,
      );
      if (mid != null) {
        exams.add(
          _ExamCountdownData(time: mid, courseCode: s.courseCode, type: 'Mid'),
        );
      }
      final fin = _parseExamDateTime(
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
    final parts = time.split(':');
    if (parts.length < 2) return 0;
    final hour = int.tryParse(parts[0]) ?? 0;
    final minute = int.tryParse(parts[1]) ?? 0;
    return hour * 60 + minute;
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

  String? _buildPhotoUrl(String? photoFilePath) {
    if (photoFilePath == null || photoFilePath.isEmpty) return null;
    final encoded = base64Url
        .encode(utf8.encode(photoFilePath))
        .replaceAll('=', '');
    return 'https://connect.bracu.ac.bd/cdn/img/thumb/$encoded.jpg';
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
                      final profile = snapshot.data?.profile ?? {};
                      final photoUrl = snapshot.data?.photoUrl;
                      final today = _todayName();
                      final todayDate = DateFormat(
                        'd MMMM, y',
                      ).format(DateTime.now());
                      final todayEntries =
                          (snapshot.data?.entries ?? [])
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
                      final nowMinutes = _timeToMinutes(
                        '${DateTime.now().hour}:${DateTime.now().minute}',
                      );
                      _ScheduleEntry? nextEntry;
                      if (todayEntries.isNotEmpty) {
                        nextEntry = _pickNextEntry(todayEntries, nowMinutes);
                      }
                      final nextExam = _nextExamCountdown(
                        snapshot.data?.sections ?? const <section.Section>[],
                      );
                      return RefreshIndicator(
                        onRefresh: _handleRefresh,
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                          physics: const AlwaysScrollableScrollPhysics(),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _TopBar(
                                name: profile['fullName'] ?? 'BRACU Student',
                                photoUrl: photoUrl,
                                onNotifications: () =>
                                    widget.onNavigate(HomeTab.notifications),
                                onProfileTap: () =>
                                    widget.onNavigate(HomeTab.profile),
                              ),
                              const SizedBox(height: 18),
                              StudentOverviewCard(
                                studentId: profile['studentId'] ?? 'N/A',
                                shortCode: profile['shortCode'] ?? '',
                                phoneNumber: profile['mobileNo'] ?? 'N/A',
                                department: profile['departmentName'] ?? 'N/A',
                                currentSemester:
                                    profile['currentSemester'] ?? 'N/A',
                                currentSessionSemesterId:
                                    profile['currentSessionSemesterId'] ?? '',
                                onLogout: widget.onLogout,
                                countdown: nextExam == null
                                    ? null
                                    : InkWell(
                                        borderRadius: BorderRadius.circular(18),
                                        onTap: () => widget.onNavigate(
                                          HomeTab.examSchedule,
                                        ),
                                        child: ExamCountdownCard(
                                          title:
                                              nextExam.time
                                                      .difference(
                                                        DateTime.now(),
                                                      )
                                                      .inDays <=
                                                  3
                                              ? '${nextExam.courseCode} ${nextExam.type} Exam'
                                              : '${nextExam.type} Exam',
                                          targetDateTime: nextExam.time,
                                        ),
                                      ),
                              ),
                              const SizedBox(height: 22),
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
                              if (todayEntries.isEmpty)
                                InkWell(
                                  onTap: () => widget.onNavigate(
                                    HomeTab.studentSchedule,
                                  ),
                                  child: const _ScheduleTile(
                                    title: 'Enjoy your day',
                                    subtitle: 'No Classes',
                                    badge: '--',
                                    color: _primary,
                                  ),
                                )
                              else
                                ...todayEntries
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
                              const SizedBox(height: 12),
                              const SizedBox(height: 10),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  const Expanded(
                                    child: _SectionTitle(title: 'Quick Access'),
                                  ),
                                  InkWell(
                                    borderRadius: BorderRadius.circular(8),
                                    onTap: () {
                                      Share.share(
                                        'https://play.google.com/store/apps/details?id=com.sabbirba.preconnect',
                                        subject:
                                            'PreConnect.app • Prepare Connect Succeed',
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
                                          Icon(
                                            Icons.share_outlined,
                                            size: 14,
                                            color: BracuPalette.textPrimary(
                                              context,
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
    required this.onNotifications,
    required this.onProfileTap,
  });

  final String name;
  final String? photoUrl;
  final VoidCallback onNotifications;
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
                          child: CachedNetworkImage(
                            imageUrl: photoUrl!,
                            fit: BoxFit.cover,
                            width: 42,
                            height: 42,
                            memCacheWidth: 84,
                            memCacheHeight: 84,
                            filterQuality: FilterQuality.low,
                            fadeInDuration: Duration.zero,
                            fadeOutDuration: Duration.zero,
                            useOldImageOnUrlChange: true,
                            placeholder: (context, url) {
                              return Center(
                                child: Text(
                                  initial.toUpperCase(),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              );
                            },
                            errorWidget: (context, url, error) {
                              return Center(
                                child: Text(
                                  initial.toUpperCase(),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              );
                            },
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
        IconButton(
          onPressed: onNotifications,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.notifications_none_outlined),
        ),
        const SizedBox(width: 2),
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
                      'PreConnect.app • Prepare Connect Succeed',
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
  });

  final Map<String, String?>? profile;
  final List<_ScheduleEntry> entries;
  final String? photoUrl;
  final List<section.Section> sections;
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
