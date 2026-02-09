import 'dart:async';
import 'dart:convert';
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
import 'package:preconnect/model/section_info.dart' as section;
import 'package:preconnect/pages/ui_kit.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  HomeTab selectedTab = HomeTab.dashboard;

  late final Map<HomeTab, Widget> pages = {
    HomeTab.dashboard: _HomeDashboard(
      onNavigate: _setTab,
      onLogout: () => _confirmLogout(context),
    ),
    HomeTab.notifications: const NotificationPage(),
    HomeTab.profile: const StudentProfile(),
    HomeTab.studentSchedule: const ClassSchedule(),
    HomeTab.examSchedule: const ExamSchedule(),
    HomeTab.alarms: const AlarmPage(),
    HomeTab.shareSchedule: const ShareSchedulePage(),
    HomeTab.scanSchedule: const ScanSchedulePage(),
    HomeTab.friendSchedule: FriendSchedulePage(onNavigate: _setTab),
    HomeTab.devs: const DevsPage(),
  };

  void _setTab(HomeTab tab) {
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
            gradient: const LinearGradient(
              colors: [Color(0xFF1E6BE3), Color(0xFF2C9DFF)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
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
                  children: const [
                    Icon(Icons.logout, color: Colors.white),
                    SizedBox(width: 8),
                    Text(
                      'Confirm Sign Out?',
                      style: TextStyle(
                        color: Colors.white,
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
                    color: Colors.white.withValues(alpha: 0.9),
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
                          foregroundColor: Colors.white,
                          side: BorderSide(
                            color: Colors.white.withValues(alpha: 0.7),
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
                          backgroundColor: Colors.white,
                          foregroundColor: const Color(0xFF1E6BE3),
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
          child: pages[selectedTab]!,
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
    unawaited(BracuAuthManager().fetchProfile());
    unawaited(BracuAuthManager().fetchStudentSchedule());
    _future = _loadData();
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
    if (scheduleJson != null && scheduleJson.trim().isNotEmpty) {
      final decoded = (jsonDecode(scheduleJson) as List<dynamic>)
          .map((e) => section.Section.fromJson(e))
          .toList();
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
    return _HomeData(profile: profile, entries: entries, photoUrl: photoUrl);
  }

  Future<void> _handleRefresh() async {
    setState(() {
      _future = _loadData(forceRefresh: true);
    });
    await _future;
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
                      final todayDate =
                          DateFormat('d MMMM, y').format(DateTime.now());
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
                                onNotifications: () => widget.onNavigate(
                                  HomeTab.notifications,
                                ),
                              ),
                              const SizedBox(height: 18),
                              _SummaryCard(
                                studentId: profile['studentId'] ?? 'N/A',
                                currentSemester:
                                    profile['currentSemester'] ?? 'N/A',
                                program: profile['program'] ?? 'N/A',
                                enrolledSemester:
                                    profile['enrolledSemester'] ?? 'N/A',
                                phone: profile['mobileNo'] ?? 'N/A',
                                onLogout: widget.onLogout,
                              ),
                              const SizedBox(height: 22),
                              Row(
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
                                      color: BracuPalette.textPrimary(context),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              if (todayEntries.isEmpty)
                                const _ScheduleTile(
                                  title: 'Enjoy your day',
                                  subtitle: 'No Classes',
                                  badge: '--',
                                  color: _primary,
                                )
                              else
                                ...todayEntries
                                    .take(3)
                                    .map(
                                      (entry) => Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 10,
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
                              const SizedBox(height: 12),
                              const SizedBox(height: 10),
                              const _SectionTitle(title: 'Quick Access'),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 12,
                                runSpacing: 12,
                                children: [
                                  _QuickActionCard(
                                    icon: Icons.person_outline,
                                    title: 'Profile',
                                    subtitle: 'Info & ID',
                                    color: _primary,
                                    onTap: () =>
                                        widget.onNavigate(HomeTab.profile),
                                  ),
                                  _QuickActionCard(
                                    icon: Icons.schedule_outlined,
                                    title: 'Schedule',
                                    subtitle: 'Classes',
                                    color: _accent,
                                    onTap: () => widget.onNavigate(
                                      HomeTab.studentSchedule,
                                    ),
                                  ),
                                  _QuickActionCard(
                                    icon: Icons.alarm_outlined,
                                    title: 'Alarms',
                                    subtitle: 'Reminders',
                                    color: const Color(0xFFFF8A34),
                                    onTap: () =>
                                        widget.onNavigate(HomeTab.alarms),
                                  ),
                                  _QuickActionCard(
                                    icon: Icons.event_note_outlined,
                                    title: 'Exams',
                                    subtitle: 'Dates',
                                    color: const Color(0xFF7C56FF),
                                    onTap: () =>
                                        widget.onNavigate(HomeTab.examSchedule),
                                  ),
                                  _QuickActionCard(
                                    icon: Icons.people_outline,
                                    title: 'Friends',
                                    subtitle: 'Schedules',
                                    color: const Color(0xFF5B8DEF),
                                    onTap: () => widget.onNavigate(
                                      HomeTab.friendSchedule,
                                    ),
                                  ),
                                  _QuickActionCard(
                                    icon: Icons.developer_mode_outlined,
                                    title: 'Devs',
                                    subtitle: 'About Us',
                                    color: const Color(0xFF2C9DFF),
                                    onTap: () => widget.onNavigate(
                                      HomeTab.devs,
                                    ),
                                  ),
                                ],
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
  });

  final String name;
  final String? photoUrl;
  final VoidCallback onNotifications;

  @override
  Widget build(BuildContext context) {
    final initial = name.isNotEmpty ? name.trim().characters.first : 'S';
    final textSecondary = BracuPalette.textSecondary(context);
    final textPrimary = BracuPalette.textPrimary(context);
    return Row(
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
                  child: Image.network(
                    photoUrl!,
                    fit: BoxFit.cover,
                    width: 42,
                    height: 42,
                    errorBuilder: (context, error, stackTrace) {
                      return Text(
                        initial.toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      );
                    },
                  ),
                ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
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
        ),
        IconButton(
          onPressed: onNotifications,
          icon: const Icon(Icons.notifications_none_outlined),
        ),
        const SizedBox(width: 4),
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

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.studentId,
    required this.currentSemester,
    required this.program,
    required this.enrolledSemester,
    required this.phone,
    required this.onLogout,
  });

  final String studentId;
  final String currentSemester;
  final String program;
  final String enrolledSemester;
  final String phone;
  final Future<void> Function() onLogout;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Student Overview',
                style: TextStyle(
                  color: BracuPalette.textPrimary(context),
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            InkWell(
              onTap: onLogout,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: BracuPalette.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.logout,
                  size: 18,
                  color: BracuPalette.primary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _InfoPill(label: 'Student ID', value: studentId),
            const SizedBox(width: 12),
            _InfoPill(label: 'Phone', value: phone),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            vertical: 10,
            horizontal: 12,
          ),
          decoration: BoxDecoration(
            color: BracuPalette.card(context),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: BracuPalette.primary.withValues(alpha: 0.14),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Program',
                style: TextStyle(
                  color: BracuPalette.textSecondary(context),
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                program,
                style: TextStyle(
                  color: BracuPalette.textPrimary(context),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final labelColor = BracuPalette.textSecondary(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: BracuPalette.card(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: BracuPalette.primary.withValues(alpha: 0.14),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(color: labelColor, fontSize: 11)),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                color: BracuPalette.textPrimary(context),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
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

class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textSecondary = BracuPalette.textSecondary(context);
    final textPrimary = BracuPalette.textPrimary(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: (MediaQuery.of(context).size.width - 52) / 2,
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
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Text(
              badge,
              style: TextStyle(
                color: color,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
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
  });

  final Map<String, String?>? profile;
  final List<_ScheduleEntry> entries;
  final String? photoUrl;
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
