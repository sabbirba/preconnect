import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/api/auth_service.dart';
import 'package:preconnect/api/exam_map_service.dart';
import 'package:preconnect/api/profile_service.dart';
import 'package:preconnect/api/personal_schedules_service.dart';
import 'package:preconnect/api/schedule_service.dart';
import 'package:preconnect/app.dart';
import 'package:preconnect/pages/class_schedule.dart';
import 'package:preconnect/pages/exam_schedule.dart';
import 'package:preconnect/pages/seat_status.dart';
import 'package:preconnect/pages/degree_progress.dart';
import 'package:preconnect/pages/alarms.dart';
import 'package:preconnect/pages/captive_wifi.dart';
import 'package:preconnect/pages/student_profile.dart';
import 'package:preconnect/pages/share_schedule.dart';
import 'package:preconnect/pages/scan_schedule.dart';
import 'package:preconnect/pages/friend_schedule.dart';
import 'package:preconnect/pages/devs.dart';
import 'package:preconnect/pages/calendar.dart';
import 'package:preconnect/pages/bus.dart';
import 'package:preconnect/pages/free_labs.dart';
import 'package:preconnect/pages/personal_schedules.dart';
import 'package:preconnect/pages/personal_schedules_sections/personal_schedules_shared.dart';
import 'package:preconnect/pages/notifications.dart';
import 'package:preconnect/pages/settings.dart';
import 'package:preconnect/pages/wifi_printer.dart';
import 'package:preconnect/pages/home_tab.dart';
import 'package:preconnect/pages/home_sections/exam_countdown.dart';
import 'package:preconnect/pages/home_sections/student_overview.dart';
import 'package:preconnect/pages/shared_widgets/current_session_helper.dart';
import 'package:preconnect/pages/shared_widgets/campus_map_shared.dart';
import 'package:preconnect/model/section_info.dart' as section;
import 'package:preconnect/model/personal_schedule.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/ads_bridge.dart';
import 'package:preconnect/tools/android_network_assist.dart';
import 'package:preconnect/tools/app_storage.dart';
import 'package:preconnect/tools/cached_image.dart';
import 'package:preconnect/tools/token_storage.dart';
import 'package:preconnect/tools/captive_wifi_http_service.dart';
import 'package:preconnect/tools/exam_sorting.dart';
import 'package:preconnect/tools/holiday_status.dart';
import 'package:preconnect/tools/ramadan_timing.dart';
import 'package:preconnect/tools/refresh_bus.dart';
import 'package:preconnect/tools/time_utils.dart';
import 'package:share_plus/share_plus.dart';

part 'home_sections/home_dashboard_data.dart';
part 'home_sections/home_dashboard_view.dart';

enum CaptiveWifiState { offline, validated, captive, unknown }

class CaptiveWifiStatus {
  const CaptiveWifiStatus({required this.state, required this.httpStatusCode});

  final CaptiveWifiState state;
  final int? httpStatusCode;
}

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

class _HomePageState extends State<HomePage> with RefreshBusState {
  HomeTab selectedTab = HomeTab.dashboard;
  StreamSubscription<HomeTab>? _shortcutTabSubscription;
  final Set<HomeTab> _returnToMoreTabs = <HomeTab>{};

  late final Map<HomeTab, WidgetBuilder> pages = {
    HomeTab.settings: (_) => const SettingsPage(),
    HomeTab.notifications: (_) => const NotificationsPage(),
    HomeTab.dashboard: (_) => _HomeDashboard(
      onNavigate: _setTab,
      onLogout: () => _confirmLogout(context),
    ),
    HomeTab.moreQuickAccess: (_) => MoreQuickAccessPage(onNavigate: _setTab),
    HomeTab.bus: (_) => const BusPage(),
    HomeTab.freeLabs: (_) => const FreeLabsPage(),
    HomeTab.calendar: (_) => const CalendarPage(),
    HomeTab.profile: (_) => const StudentProfile(),
    HomeTab.studentSchedule: (_) => const ClassSchedule(),
    HomeTab.examSchedule: (_) => const ExamSchedule(),
    HomeTab.seatStatus: (_) => const SeatStatusPage(),
    HomeTab.degreeProgress: (_) => const DegreeProgressPage(),
    HomeTab.alarms: (_) => const AlarmPage(),
    HomeTab.shareSchedule: (_) => const ShareSchedulePage(),
    HomeTab.scanSchedule: (_) => const ScanSchedulePage(),
    HomeTab.friendSchedule: (_) => FriendSchedulePage(onNavigate: _setTab),
    HomeTab.campusPrinter: (_) => const CampusPrinterPage(),
    HomeTab.devs: (_) => const DevsPage(),
    HomeTab.personalSchedules: (_) => const PersonalSchedulesPage(),
  };
  late final List<HomeTab> _tabOrder = HomeTab.values;
  final Set<HomeTab> _builtTabs = {HomeTab.dashboard};

  @override
  void initState() {
    super.initState();
    final pendingShortcutTab = HomePage.takePendingShortcutTab();
    if (pendingShortcutTab != null) {
      selectedTab = pendingShortcutTab;
      _builtTabs.add(pendingShortcutTab);
    }
    HomeTabRegistry.setActive(selectedTab);
    HomeTabRegistry.activeTab.addListener(_onRegistryTabChanged);
    _shortcutTabSubscription = HomePage._shortcutTabController.stream.listen((
      tab,
    ) {
      if (!mounted) return;
      _setTab(tab);
    });
    unawaited(AlarmPage.preload());
    unawaited(ClassSchedule.preload());
    unawaited(ExamSchedule.preload());
    unawaited(PersonalSchedulesPage.preload());
  }

  @override
  void dispose() {
    _shortcutTabSubscription?.cancel();
    HomeTabRegistry.activeTab.removeListener(_onRegistryTabChanged);
    super.dispose();
  }

  void _onRegistryTabChanged() {
    if (!context.mounted) return;
    final requestedTab = HomeTabRegistry.activeTab.value;
    if (requestedTab == selectedTab) return;
    _setTab(requestedTab);
  }

  void _setTab(HomeTab tab) {
    if (selectedTab == tab) {
      HomeTabRegistry.setActive(tab);
      return;
    }
    if (selectedTab == HomeTab.moreQuickAccess &&
        tab != HomeTab.moreQuickAccess) {
      _returnToMoreTabs.add(tab);
    }
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
      return;
    }
    if (_returnToMoreTabs.remove(selectedTab)) {
      _setTab(HomeTab.moreQuickAccess);
    } else {
      _setTab(HomeTab.dashboard);
    }
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final navigator = Navigator.of(context);
    final themeNotifier = ThemeController.of(context);
    final shouldLogout = await showBracuConfirmationDialog(
      context,
      icon: Icons.logout,
      title: 'Confirm Sign Out?',
      message:
          'Sign out will clear stored data. You can sign in again for fresh data.',
      confirmLabel: 'Sign Out',
    );
    if (!mounted) return;

    if (shouldLogout) {
      await AuthService().logout(instant: true);
      if (!mounted) return;
      themeNotifier.value = ThemeMode.system;
      RefreshBus.instance.notify(reason: 'auth');
      if (!mounted) return;
      navigator.pushNamedAndRemoveUntil('/onboarding', (route) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: selectedTab == HomeTab.dashboard,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && selectedTab != HomeTab.dashboard) {
          _handleBack();
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

class _CaptiveWifiBanner extends StatelessWidget {
  const _CaptiveWifiBanner({required this.onOpenLogin, this.statusCode});

  final VoidCallback onOpenLogin;
  final int? statusCode;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: BracuPalette.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: BracuPalette.primary.withValues(alpha: 0.20),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.wifi_lock_rounded, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Captive Wi-Fi login required',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: BracuPalette.textPrimary(context),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            statusCode == null
                ? 'Connected to Wi-Fi but internet is behind captive Wi-Fi.'
                : 'Connected to Wi-Fi but internet is behind captive Wi-Fi (probe: HTTP $statusCode).',
            style: TextStyle(
              fontSize: 12,
              color: BracuPalette.textSecondary(context),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 34,
            child: ElevatedButton.icon(
              onPressed: onOpenLogin,
              icon: const Icon(Icons.login_rounded, size: 16),
              label: const Text('One-Tap Captive Wi-Fi'),
            ),
          ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.name,
    required this.photoUrl,
    required this.onOpenNotifications,
    required this.onProfileTap,
  });

  final String name;
  final String? photoUrl;
  final VoidCallback onOpenNotifications;
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
                            placeholder: const BracuShimmer(
                              child: BracuSkeletonBox(
                                width: 42,
                                height: 42,
                                radius: 14,
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
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Welcome Back',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: textSecondary),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        BracuNotificationsIconButton(
          onTap: onOpenNotifications,
          iconSize: 22,
          padding: 8,
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
      child: LayoutBuilder(
        builder: (context, constraints) {
          final rightColumnWidth = (constraints.maxWidth * 0.30).clamp(
            96.0,
            128.0,
          );
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionBadge(label: badge, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w400,
                        color: textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 12),
                SizedBox(
                  width: rightColumnWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        trailing!,
                        textAlign: TextAlign.right,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: textPrimary,
                        ),
                      ),
                      if (trailingSub != null &&
                          trailingSub!.trim().isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          trailingSub!,
                          textAlign: TextAlign.right,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11, color: textSecondary),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          );
        },
      ),
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
      return SizedBox(
        width: 52,
        child: Column(
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
        ),
      );
    }

    final units = <({String value, String label})>[
      (value: hours.toString().padLeft(2, '0'), label: 'Hours'),
      (value: minutes.toString().padLeft(2, '0'), label: 'Minutes'),
      (value: seconds.toString().padLeft(2, '0'), label: 'Seconds'),
    ];

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

class _HomeData {
  _HomeData({
    required this.profile,
    required this.entries,
    required this.photoUrl,
    required this.sections,
    required this.examOverrides,
    required this.personalSchedules,
    required this.isRamadan,
    required this.ramadan,
    required this.holiday,
    required this.cardVisibility,
    this.scheduleJson,
  });

  final Map<String, String?>? profile;
  final List<_ScheduleEntry> entries;
  final String? photoUrl;
  final List<section.Section> sections;
  final Map<String, ExamScheduleOverride> examOverrides;
  final List<PersonalSchedule> personalSchedules;
  final bool isRamadan;
  final RamadanStatus ramadan;
  final HolidayStatus holiday;
  final HomeCardVisibility cardVisibility;
  final String? scheduleJson;

  _HomeData copyWith({HomeCardVisibility? cardVisibility}) {
    return _HomeData(
      profile: profile,
      entries: entries,
      photoUrl: photoUrl,
      sections: sections,
      examOverrides: examOverrides,
      personalSchedules: personalSchedules,
      isRamadan: isRamadan,
      ramadan: ramadan,
      holiday: holiday,
      cardVisibility: cardVisibility ?? this.cardVisibility,
      scheduleJson: scheduleJson,
    );
  }

  Map<String, dynamic> toCacheJson() {
    return <String, dynamic>{
      'profile': profile,
      'photoUrl': photoUrl,
      'scheduleJson': scheduleJson,
      'personalSchedules': personalSchedules
          .map((item) => item.toJson())
          .toList(),
      'isRamadan': isRamadan,
      'ramadan': {
        'isRamadan': ramadan.isRamadan,
        'sehriEndsAt': ramadan.sehriEndsAt,
        'iftarAt': ramadan.iftarAt,
      },
      'holiday': holiday.toCacheJson(),
      'cardVisibility': {
        'showQuickAccessSection': cardVisibility.showQuickAccessSection,
        'showRamadanCard': cardVisibility.showRamadanCard,
        'showTodaySchedule': cardVisibility.showTodaySchedule,
        'showExamCountdownCard': cardVisibility.showExamCountdownCard,
        'showSponsoredContent': cardVisibility.showSponsoredContent,
      },
      'sections': scheduleJson,
      'examOverrides': examOverrides.map(
        (key, value) => MapEntry(key, <String, dynamic>{
          'midDate': value.midDate,
          'midStartTime': value.midStartTime,
          'midEndTime': value.midEndTime,
          'midRoomNumber': value.midRoomNumber,
          'finalDate': value.finalDate,
          'finalStartTime': value.finalStartTime,
          'finalEndTime': value.finalEndTime,
          'finalRoomNumber': value.finalRoomNumber,
        }),
      ),
    };
  }

  static _HomeData? fromCache(Map<String, dynamic> json) {
    final profileJson = json['profile'];
    final profile = profileJson is Map
        ? profileJson.map((key, value) => MapEntry('$key', value?.toString()))
        : null;
    final scheduleJson = json['scheduleJson']?.toString();
    final sections = section.parseSectionsFromScheduleJson(scheduleJson);
    final entries = <_ScheduleEntry>[];
    for (final sectionItem in sections) {
      for (final classSchedule in sectionItem.sectionSchedule.classSchedules) {
        entries.add(
          _ScheduleEntry(
            day: classSchedule.day,
            startTime: classSchedule.startTime,
            endTime: classSchedule.endTime,
            courseCode: sectionItem.courseCode,
            sectionName: sectionItem.sectionName,
            roomNumber: sectionItem.roomNumber,
            faculties: sectionItem.faculties,
          ),
        );
      }
    }
    final personalSchedulesJson = json['personalSchedules'];
    final personalSchedules = personalSchedulesJson is List
        ? personalSchedulesJson
              .whereType<Map>()
              .map(
                (item) =>
                    PersonalSchedule.fromJson(Map<String, dynamic>.from(item)),
              )
              .toList(growable: false)
        : const <PersonalSchedule>[];
    final ramadanJson = json['ramadan'];
    final ramadan = ramadanJson is Map
        ? RamadanStatus(
            isRamadan: ramadanJson['isRamadan'] == true,
            sehriEndsAt: ramadanJson['sehriEndsAt']?.toString(),
            iftarAt: ramadanJson['iftarAt']?.toString(),
          )
        : const RamadanStatus(isRamadan: false);
    final holidayJson = json['holiday'];
    final holiday = holidayJson is Map
        ? HolidayStatus.fromCache(holidayJson)
        : HolidayStatus.empty;
    final visibilityJson = json['cardVisibility'];
    final cardVisibility = visibilityJson is Map
        ? HomeCardVisibility(
            showQuickAccessSection:
                visibilityJson['showQuickAccessSection'] == true,
            showRamadanCard: visibilityJson['showRamadanCard'] == true,
            showTodaySchedule: visibilityJson['showTodaySchedule'] == true,
            showExamCountdownCard:
                visibilityJson['showExamCountdownCard'] == true,
            showSponsoredContent:
                visibilityJson['showSponsoredContent'] == true,
          )
        : HomeCardPreferences.defaults;
    final overridesJson = json['examOverrides'];
    final examOverrides = <String, ExamScheduleOverride>{};
    if (overridesJson is Map) {
      for (final entry in overridesJson.entries) {
        final raw = entry.value;
        if (raw is! Map) continue;
        final map = Map<String, dynamic>.from(raw);
        examOverrides[entry.key.toString()] = ExamScheduleOverride(
          midDate: map['midDate']?.toString(),
          midStartTime: map['midStartTime']?.toString(),
          midEndTime: map['midEndTime']?.toString(),
          midRoomNumber: map['midRoomNumber']?.toString(),
          finalDate: map['finalDate']?.toString(),
          finalStartTime: map['finalStartTime']?.toString(),
          finalEndTime: map['finalEndTime']?.toString(),
          finalRoomNumber: map['finalRoomNumber']?.toString(),
        );
      }
    }
    return _HomeData(
      profile: profile,
      entries: entries,
      photoUrl: json['photoUrl']?.toString(),
      sections: sections,
      examOverrides: examOverrides,
      personalSchedules: personalSchedules,
      isRamadan: ramadan.isRamadan,
      ramadan: ramadan,
      holiday: holiday,
      cardVisibility: cardVisibility,
      scheduleJson: scheduleJson,
    );
  }
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

class _CountdownCardData {
  _CountdownCardData({
    required this.title,
    required this.targetDateTime,
    required this.tab,
  });

  final String title;
  final DateTime targetDateTime;
  final HomeTab tab;
}

class _TodayExamEntry {
  _TodayExamEntry({
    required this.dateTime,
    required this.courseCode,
    required this.type,
    required this.sectionName,
    required this.faculties,
    required this.startTime,
    required this.endTime,
    required this.room,
  });

  final DateTime dateTime;
  final String courseCode;
  final String type;
  final String sectionName;
  final String faculties;
  final String? startTime;
  final String? endTime;
  final String? room;
}

class MoreQuickAccessPage extends StatefulWidget {
  const MoreQuickAccessPage({super.key, required this.onNavigate});

  final ValueChanged<HomeTab> onNavigate;

  @override
  State<MoreQuickAccessPage> createState() => _MoreQuickAccessPageState();
}

class _MoreQuickAccessPageState extends State<MoreQuickAccessPage> {
  @override
  Widget build(BuildContext context) {
    return BracuPageScaffold(
      title: 'More',
      subtitle: 'Options',
      icon: Icons.more_horiz_rounded,
      body: ListView(
        padding: kBracuPageListPadding,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final layout = quickAccessGridLayout(constraints.maxWidth);
              return Center(
                child: Wrap(
                  alignment: WrapAlignment.center,
                  runAlignment: WrapAlignment.center,
                  spacing: layout.spacing,
                  runSpacing: layout.spacing,
                  children: [
                    QuickAccessCard(
                      width: layout.itemWidth,
                      icon: Icons.directions_bus_rounded,
                      title: 'Bus',
                      subtitle: 'Routes',
                      color: const Color(0xFF1E6BE3),
                      onTap: () => widget.onNavigate(HomeTab.bus),
                    ),
                    QuickAccessCard(
                      width: layout.itemWidth,
                      icon: Icons.local_printshop_outlined,
                      title: 'Printer',
                      subtitle: 'Campus',
                      color: const Color(0xFF22B573),
                      onTap: () => widget.onNavigate(HomeTab.campusPrinter),
                    ),
                    QuickAccessCard(
                      width: layout.itemWidth,
                      icon: Icons.computer_outlined,
                      title: 'Free',
                      subtitle: 'Labs',
                      color: const Color(0xFF00A8E8),
                      onTap: () => widget.onNavigate(HomeTab.freeLabs),
                    ),
                    QuickAccessCard(
                      width: layout.itemWidth,
                      icon: Icons.insights_outlined,
                      title: 'Seat',
                      subtitle: 'Status',
                      color: const Color(0xFF00A8E8),
                      onTap: () => widget.onNavigate(HomeTab.seatStatus),
                    ),
                    QuickAccessCard(
                      width: layout.itemWidth,
                      icon: Icons.calendar_today_outlined,
                      title: 'Events',
                      subtitle: 'Calendar',
                      color: const Color(0xFF00A86B),
                      onTap: () => widget.onNavigate(HomeTab.calendar),
                    ),
                    QuickAccessCard(
                      width: layout.itemWidth,
                      icon: Icons.developer_mode_outlined,
                      title: 'Devs',
                      subtitle: 'Support',
                      color: const Color(0xFF2C9DFF),
                      onTap: () => widget.onNavigate(HomeTab.devs),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
