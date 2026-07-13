import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/api/auth.dart';
import 'package:preconnect/api/exam_map.dart';
import 'package:preconnect/api/profile.dart';
import 'package:preconnect/api/custom_schedules.dart';
import 'package:preconnect/api/schedule.dart';
import 'package:preconnect/pages/class_schedule.dart';
import 'package:preconnect/pages/exam_schedule.dart';
import 'package:preconnect/pages/degree_progress.dart';
import 'package:preconnect/pages/alarms.dart';
import 'package:preconnect/pages/free_labs.dart';
import 'package:preconnect/pages/student_profile.dart';
import 'package:preconnect/pages/share_schedule.dart';
import 'package:preconnect/pages/scan_schedule.dart';
import 'package:preconnect/pages/friend_schedule.dart';
import 'package:preconnect/pages/devs.dart';
import 'package:preconnect/pages/calendar.dart';
import 'package:preconnect/pages/bus.dart';
import 'package:preconnect/pages/seat_status.dart';
import 'package:preconnect/pages/custom_schedules.dart';
import 'package:preconnect/pages/custom_schedules_sections/schedules_shared.dart';
import 'package:preconnect/pages/notifications.dart';
import 'package:preconnect/pages/settings.dart';
import 'package:preconnect/pages/wifi_printer.dart';
import 'package:preconnect/libsync/libsync_page.dart';
import 'package:preconnect/pages/dspace_browser.dart';
import 'package:preconnect/pages/wishlist.dart';
import 'package:share_plus/share_plus.dart';
import 'package:preconnect/pages/home_tab.dart';
import 'package:preconnect/pages/home_sections/exam_countdown.dart';
import 'package:preconnect/pages/home_sections/student_overview.dart';
import 'package:preconnect/pages/shared_widgets/session_helper.dart';
import 'package:preconnect/pages/shared_widgets/map_shared.dart';
import 'package:preconnect/pages/shared_widgets/exam_filter.dart';
import 'package:preconnect/model/section_info.dart' as section;
import 'package:preconnect/model/custom_schedule.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/network_assist.dart';
import 'package:preconnect/tools/cached_image.dart';
import 'package:preconnect/tools/quiet_controller.dart';
import 'package:preconnect/api/repository_cache.dart';
import 'package:preconnect/tools/app_storage.dart';
import 'package:preconnect/tools/token_storage.dart';
import 'package:preconnect/tools/wifi_http.dart';
import 'package:preconnect/tools/string_utils.dart';
import 'package:preconnect/tools/exam_visibility.dart';
import 'package:preconnect/tools/holiday.dart';
import 'package:preconnect/tools/ramadan.dart';
import 'package:preconnect/tools/refresh_bus.dart';
import 'package:preconnect/tools/snapshot_store.dart';
import 'package:preconnect/api/fcm.dart';
import 'package:preconnect/tools/storage_keys.dart';
import 'package:preconnect/tools/time_utils.dart';

part 'home_sections/dashboard_data.dart';
part 'home_sections/dashboard_view.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, this.initialTab = HomeTab.dashboard});

  final HomeTab initialTab;

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
  late final Map<HomeTab, WidgetBuilder> pages = {
    HomeTab.settings: (_) => const SettingsPage(),
    HomeTab.notifications: (_) => const NotificationsPage(),
    HomeTab.dashboard: (_) => _HomeDashboard(
      onNavigate: _setTab,
      onLogout: () => _confirmLogout(context),
    ),
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
    HomeTab.personalSchedules: (_) => const CustomSchedulesPage(),
    HomeTab.libSync: (_) => const LibSyncPage(),
    HomeTab.dspace: (_) => const DSpaceBrowserPage(),
    HomeTab.wishlist: (_) => const WishlistPage(),
  };
  late final List<HomeTab> _tabOrder = HomeTab.values;
  final Set<HomeTab> _builtTabs = {HomeTab.dashboard};

  @override
  void initState() {
    super.initState();
    selectedTab = widget.initialTab;
    final pendingShortcutTab = HomePage.takePendingShortcutTab();
    if (pendingShortcutTab != null) {
      selectedTab = pendingShortcutTab;
      _builtTabs.add(pendingShortcutTab);
    } else {
      _builtTabs.add(selectedTab);
    }
    HomeTabRegistry.setActive(selectedTab);
    HomeTabRegistry.activeTab.addListener(_onRegistryTabChanged);
    _shortcutTabSubscription = HomePage._shortcutTabController.stream.listen((
      tab,
    ) {
      if (!mounted) return;
      _setTab(tab);
    });
    unawaited(_persistSelectedTab(selectedTab));
    unawaited(_preloadPrimaryHomeTabs());
    if (!kIsWeb) {
      unawaited(
        Future.wait(<Future<void>>[
          AlarmPage.preload().catchError((_) {}),
          CustomSchedulesPage.preload().catchError((_) {}),
          CampusPrinterPage.preload().catchError((_) {}),
        ]).then((_) async {
          await QuietModeController.instance.refresh();
          await InAppReviewPrompt.maybePrompt();
        }),
      );
    }
  }

  Future<void> _preloadPrimaryHomeTabs() async {
    await Future.wait(<Future<void>>[
      StudentProfile.preload().catchError((_) {}),
      ClassSchedule.preload().catchError((_) {}),
      ExamSchedule.preload().catchError((_) {}),
    ]);
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
      unawaited(_persistSelectedTab(tab));
      return;
    }
    final shouldJumpClass = tab == HomeTab.studentSchedule;
    final shouldJumpExam = tab == HomeTab.examSchedule;
    setState(() {
      selectedTab = tab;
    });
    HomeTabRegistry.setActive(tab);
    unawaited(_persistSelectedTab(tab));
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

  Future<void> _persistSelectedTab(HomeTab tab) async {
    try {
      await RepositoryCache.instance.writeString(StorageKeys.homeTab, tab.name);
    } catch (_) {}
  }

  void _handleBack() {
    if (selectedTab == HomeTab.dashboard) return;
    if (selectedTab == HomeTab.scanSchedule ||
        selectedTab == HomeTab.shareSchedule) {
      _setTab(HomeTab.friendSchedule);
      return;
    }
    _setTab(HomeTab.dashboard);
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final logoutContext = context;
    if (!logoutContext.mounted) return;
    await showBracuConfirmationWithActionDialog(
      context,
      icon: Icons.logout,
      title: 'Confirm Sign Out?',
      message:
          'Sign out will clear stored data. You can sign in again for fresh data.',
      confirmLabel: 'Sign Out',
      confirmColor: BracuPalette.danger,
      onConfirm: () async {
        await AuthService().logout(context: logoutContext, force: true);
      },
    );
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

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.name,
    required this.photoUrl,
    required this.showNotificationsIcon,
    required this.onOpenNotifications,
    required this.onProfileTap,
  });

  final String name;
  final String? photoUrl;
  final bool showNotificationsIcon;
  final VoidCallback onOpenNotifications;
  final VoidCallback onProfileTap;

  @override
  Widget build(BuildContext context) {
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
                if (photoUrl != null) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: CachedImage(
                      url: photoUrl!,
                      fit: BoxFit.cover,
                      width: 42,
                      height: 42,
                      filterQuality: FilterQuality.low,
                      placeholder: const SizedBox.shrink(),
                      error: const SizedBox.shrink(),
                    ),
                  ),
                  const Gap(12),
                ],
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
                      const Gap(2),
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
        if (showNotificationsIcon)
          BracuNotificationsIconButton(
            onTap: onOpenNotifications,
            iconSize: 28,
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
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SectionBadge(label: badge, color: color),
              const Gap(12),
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
                    const Gap(4),
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
                const Gap(12),
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
                        const Gap(2),
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
            const Gap(5),
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
        const Gap(6),
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
                    const Gap(2),
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
              const Gap(8),
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
            const Gap(2),
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
          if (i != units.length - 1) const Gap(8),
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
    this.advisingInfo,
  });

  final Map<String, String?>? profile;
  final List<_ScheduleEntry> entries;
  final String? photoUrl;
  final List<section.Section> sections;
  final Map<String, ExamScheduleOverride> examOverrides;
  final List<CustomSchedule> personalSchedules;
  final bool isRamadan;
  final RamadanStatus ramadan;
  final HolidayStatus holiday;
  final HomeCardVisibility cardVisibility;
  final String? scheduleJson;
  final Map<String, String?>? advisingInfo;

  bool get hasRequiredProfileFields {
    final profileData = profile;
    if (profileData == null) return false;
    final studentId = (profileData['studentId'] ?? '').trim();
    final fullName = (profileData['fullName'] ?? '').trim();
    final shortCode = (profileData['shortCode'] ?? '').trim();
    final departmentName = (profileData['departmentName'] ?? '').trim();
    final currentSemester = (profileData['currentSemester'] ?? '').trim();
    return studentId.isNotEmpty &&
        fullName.isNotEmpty &&
        shortCode.isNotEmpty &&
        departmentName.isNotEmpty &&
        currentSemester.isNotEmpty;
  }

  _HomeData copyWith({
    HomeCardVisibility? cardVisibility,
    Map<String, String?>? advisingInfo,
  }) {
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
      advisingInfo: advisingInfo ?? this.advisingInfo,
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
        'showDecorations': cardVisibility.showDecorations,
        'showCampusMapContacts': cardVisibility.showCampusMapContacts,
        'showNotificationsIcon': cardVisibility.showNotificationsIcon,
        'showFundingSection': cardVisibility.showFundingSection,
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
      'advisingInfo': advisingInfo,
    };
  }

  static _HomeData? fromCache(Map<String, dynamic> json) {
    final profileJson = json['profile'];
    final profile = profileJson is Map
        ? profileJson.map((key, value) => MapEntry('$key', value?.toString()))
        : null;
    final scheduleJson = json['scheduleJson']?.toString();
    final sections = section.parseSectionsFromScheduleJson(scheduleJson);
    final personalSchedulesJson = json['personalSchedules'];
    final personalSchedules = personalSchedulesJson is List
        ? personalSchedulesJson
              .whereType<Map>()
              .map(
                (item) =>
                    CustomSchedule.fromJson(Map<String, dynamic>.from(item)),
              )
              .toList(growable: false)
        : const <CustomSchedule>[];
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
            showDecorations: visibilityJson['showDecorations'] == true,
            showTodaySchedule: visibilityJson['showTodaySchedule'] == true,
            showExamCountdownCard:
                visibilityJson['showExamCountdownCard'] == true,
            showCampusMapContacts:
                visibilityJson['showCampusMapContacts'] == true,
            showNotificationsIcon:
                visibilityJson['showNotificationsIcon'] == true,
            showFundingSection: visibilityJson['showFundingSection'] == true,
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
    final entries = <_ScheduleEntry>[];
    for (final sectionItem in sections) {
      if (CourseSectionExamFilter.isFinishedAfterFinalExam(
        section: sectionItem,
        overrides: examOverrides,
      )) {
        continue;
      }
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
    final advisingJson = json['advisingInfo'];
    final advisingInfo = advisingJson is Map
        ? advisingJson.map((key, value) => MapEntry('$key', value?.toString()))
        : null;
    final data = _HomeData(
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
      advisingInfo: advisingInfo,
    );
    return data.hasRequiredProfileFields ? data : null;
  }
}

class _CountdownCardData {
  _CountdownCardData({
    required this.title,
    required this.targetDateTime,
    required this.tab,
    this.subtitle,
  });

  final String title;
  final DateTime targetDateTime;
  final HomeTab tab;
  final String? subtitle;
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

class _ScheduleEntry {
  const _ScheduleEntry({
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
  final String? roomNumber;
  final String? faculties;
}
