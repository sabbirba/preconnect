import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'dart:io';
import 'package:android_intent_plus/android_intent.dart';
import 'package:preconnect/tools/local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:preconnect/pages/notification_sections/notification_tile.dart';
import 'package:preconnect/pages/notification_sections/setting_tile.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:preconnect/model/notification_item.dart';
import 'package:preconnect/tools/notification_store.dart';
import 'package:preconnect/tools/refresh_bus.dart';
import 'package:preconnect/api/bracu_auth_manager.dart';
import 'package:preconnect/model/section_info.dart';

class NotificationPage extends StatefulWidget {
  const NotificationPage({super.key});

  @override
  State<NotificationPage> createState() => _NotificationPageState();
}

class _NotificationPageState extends State<NotificationPage>
    with WidgetsBindingObserver {
  bool allEnabled = false;
  bool classReminders = false;
  bool examUpdates = false;
  bool friendUpdates = false;
  bool systemAlerts = false;
  bool systemGranted = true;
  bool _loading = true;
  List<NotificationItem> _items = [];
  bool _scheduling = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
    RefreshBus.instance.addListener(_onRefreshSignal);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    RefreshBus.instance.removeListener(_onRefreshSignal);
    super.dispose();
  }

  void _onRefreshSignal() {
    if (!mounted) return;
    if (RefreshBus.instance.reason == 'notifications') {
      return;
    }
    unawaited(_syncSchedules());
    unawaited(_reloadItems());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkSystemPermission().then((value) {
        if (!mounted) return;
        setState(() {
          systemGranted = value;
        });
      });
    }
  }

  Future<void> _bootstrap() async {
    try {
      await LocalNotificationsService.instance.initialize();
      final prefs = await SharedPreferences.getInstance();
      allEnabled = prefs.getBool('notif_all') ?? false;
      classReminders = prefs.getBool('notif_class') ?? false;
      examUpdates = prefs.getBool('notif_exam') ?? false;
      friendUpdates = prefs.getBool('notif_friend') ?? false;
      systemAlerts = prefs.getBool('notif_system') ?? false;
      _syncAllEnabled();
      systemGranted = await _checkSystemPermission();
      _items = await NotificationStore.load();
      await _syncSchedules();
    } catch (_) {
      // Keep UI responsive even if scheduling fails.
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _reloadItems() async {
    final items = await NotificationStore.load();
    if (!mounted) return;
    setState(() {
      _items = items;
    });
  }

  Future<void> _savePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notif_all', allEnabled);
    await prefs.setBool('notif_class', classReminders);
    await prefs.setBool('notif_exam', examUpdates);
    await prefs.setBool('notif_friend', friendUpdates);
    await prefs.setBool('notif_system', systemAlerts);
  }

  Future<bool> _checkSystemPermission() async {
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      return true;
    }
    final status = await Permission.notification.status;
    return status.isGranted || status.isLimited;
  }

  Future<bool> _ensureSystemPermission() async {
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      return true;
    }
    final status = await Permission.notification.request();
    return status.isGranted || status.isLimited;
  }

  void _syncAllEnabled() {
    final enabled =
        classReminders && examUpdates && friendUpdates && systemAlerts;
    if (allEnabled != enabled) {
      allEnabled = enabled;
    }
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    showAppSnackBar(context, message);
  }

  Future<void> _toggleAll(bool value) async {
    if (value && !systemGranted) {
      final granted = await _ensureSystemPermission();
      if (!granted) {
        _showSnackBar('Enable notifications in system settings.');
        return;
      }
      systemGranted = true;
    }
    if (value) {
      await _requestExactAlarmOnce();
    }
    setState(() {
      allEnabled = value;
      classReminders = value;
      examUpdates = value;
      friendUpdates = value;
      systemAlerts = value;
    });
    await _savePrefs();
    await _syncSchedules();
    RefreshBus.instance.notify(reason: 'notifications');
    if (value) {
      await _pushLocalNotification(
        title: 'PreConnect',
        body: 'Notifications are enabled.',
        category: 'system',
      );
    }
  }

  Future<void> _pushLocalNotification({
    required String title,
    required String body,
    required String category,
  }) async {
    final now = DateTime.now().toUtc();
    final id = now.millisecondsSinceEpoch.remainder(1000000000);
    final item = NotificationItem(
      id: id,
      title: title,
      message: body,
      timeIso: now.toIso8601String(),
      category: category,
    );
    await LocalNotificationsService.instance.showLocalNotification(
      id: id,
      title: title,
      body: body,
    );
    setState(() {
      _items.insert(0, item);
    });
    await NotificationStore.add(item);
  }

  Future<void> _deleteNotification(NotificationItem item) async {
    setState(() {
      _items.removeWhere((e) => e.id == item.id);
    });
    await NotificationStore.delete(item.id);
  }

  Future<void> _toggleSetting(bool value, void Function(bool) apply) async {
    if (value && !systemGranted) {
      final granted = await _ensureSystemPermission();
      if (!granted) {
        _showSnackBar('Enable notifications in system settings.');
        return;
      }
      systemGranted = true;
    }
    if (value) {
      await _requestExactAlarmOnce();
    }
    setState(() {
      apply(value);
      _syncAllEnabled();
    });
    await _savePrefs();
    await _syncSchedules();
    RefreshBus.instance.notify(reason: 'notifications');
  }

  Future<void> _syncSchedules() async {
    if (_scheduling) return;
    _scheduling = true;
    try {
      await LocalNotificationsService.instance.initialize();
      final prefs = await SharedPreferences.getInstance();
      final classIds = prefs.getStringList('notif_ids_class') ?? const [];
      final examIds = prefs.getStringList('notif_ids_exam') ?? const [];
      final idsToCancel = [
        ...classIds.map(int.parse),
        ...examIds.map(int.parse),
      ];
      await LocalNotificationsService.instance.cancel(idsToCancel);

      final scheduleJson = await BracuAuthManager().getStudentSchedule();
      if (scheduleJson == null || scheduleJson.trim().isEmpty) {
        await prefs.setStringList('notif_ids_class', []);
        await prefs.setStringList('notif_ids_exam', []);
        return;
      }

      final sections = (jsonDecode(scheduleJson) as List<dynamic>)
          .map((e) => Section.fromJson(e))
          .toList();

      if (allEnabled && classReminders) {
        final classIdsNew = await _scheduleClassReminders(sections);
        await prefs.setStringList(
          'notif_ids_class',
          classIdsNew.map((e) => e.toString()).toList(),
        );
      } else {
        await prefs.setStringList('notif_ids_class', []);
      }

      if (allEnabled && examUpdates) {
        final examIdsNew = await _scheduleExamReminders(sections);
        await prefs.setStringList(
          'notif_ids_exam',
          examIdsNew.map((e) => e.toString()).toList(),
        );
      } else {
        await prefs.setStringList('notif_ids_exam', []);
      }
    } catch (_) {
      // Ignore scheduling errors to avoid blocking UI.
    } finally {
      _scheduling = false;
    }
  }

  Future<List<int>> _scheduleClassReminders(List<Section> sections) async {
    const lead = Duration(minutes: 30);
    final now = DateTime.now();
    final ids = <int>[];

    for (final section in sections) {
      final schedule = section.sectionSchedule;
      final start = DateTime.tryParse(schedule.classStartDate);
      final end = DateTime.tryParse(schedule.classEndDate);
      for (final cls in schedule.classSchedules) {
        final weekday = _weekdayFromName(cls.day);
        if (weekday == null) continue;
        for (var i = 0; i <= 7; i++) {
          final date = now.add(Duration(days: i));
          if (date.weekday != weekday) continue;
          if (start != null && date.isBefore(start)) continue;
          if (end != null && date.isAfter(end)) continue;
          final time = _parseTime(cls.startTime);
          if (time == null) continue;
          final scheduledAt = DateTime(
            date.year,
            date.month,
            date.day,
            time.hour,
            time.minute,
          ).subtract(lead);
          if (scheduledAt.isBefore(now)) continue;
          final id = _buildId(section.sectionId, 'class', scheduledAt);
          await LocalNotificationsService.instance.scheduleNotification(
            id: id,
            scheduledAt: scheduledAt,
            title: '${section.courseCode} Class',
            body: 'Starts at ${cls.startTime} in ${section.roomNumber}.',
          );
          ids.add(id);
        }
      }
    }
    return ids;
  }

  Future<List<int>> _scheduleExamReminders(List<Section> sections) async {
    final now = DateTime.now();
    final ids = <int>[];

    for (final section in sections) {
      final schedule = section.sectionSchedule;
      final mid = _parseExamDateTime(
        schedule.midExamDate,
        schedule.midExamStartTime,
      );
      final fin = _parseExamDateTime(
        schedule.finalExamDate,
        schedule.finalExamStartTime,
      );
      final times = <DateTime?>[mid, fin];
      for (final examTime in times) {
        if (examTime == null || examTime.isBefore(now)) continue;
        var scheduledAt = examTime.subtract(const Duration(hours: 24));
        if (scheduledAt.isBefore(now)) {
          scheduledAt = examTime.subtract(const Duration(hours: 1));
        }
        if (scheduledAt.isBefore(now)) continue;
        final id = _buildId(section.sectionId, 'exam', scheduledAt);
        final title = '${section.courseCode} Exam';
        final body = 'Exam at ${_formatTimeOnly(examTime)}';
        await LocalNotificationsService.instance.scheduleNotification(
          id: id,
          scheduledAt: scheduledAt,
          title: title,
          body: body,
        );
        ids.add(id);
      }
    }
    return ids;
  }

  int _buildId(int sectionId, String type, DateTime time) {
    final base = time.millisecondsSinceEpoch ~/ 60000;
    final typeHash = type == 'exam' ? 2 : 1;
    return ((sectionId * 1000003) + base + typeHash) % 1000000000;
  }

  int? _weekdayFromName(String day) {
    switch (day.toUpperCase()) {
      case 'MONDAY':
        return DateTime.monday;
      case 'TUESDAY':
        return DateTime.tuesday;
      case 'WEDNESDAY':
        return DateTime.wednesday;
      case 'THURSDAY':
        return DateTime.thursday;
      case 'FRIDAY':
        return DateTime.friday;
      case 'SATURDAY':
        return DateTime.saturday;
      case 'SUNDAY':
        return DateTime.sunday;
      default:
        return null;
    }
  }

  DateTime? _parseExamDateTime(String? date, String? time) {
    if (date == null || time == null) return null;
    final parsedDate = DateTime.tryParse(date);
    final parsedTime = _parseTime(time);
    if (parsedDate == null || parsedTime == null) return null;
    return DateTime(
      parsedDate.year,
      parsedDate.month,
      parsedDate.day,
      parsedTime.hour,
      parsedTime.minute,
    );
  }

  TimeOfDay? _parseTime(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final parts = raw.split(':');
    if (parts.length < 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    return TimeOfDay(hour: hour, minute: minute);
  }

  String _formatTimeOnly(DateTime dt) {
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final min = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$min $ampm';
  }

  String _formatTime(String iso) {
    if (iso.isEmpty) return '';
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return iso;
    final now = DateTime.now();
    final isToday =
        now.year == dt.year && now.month == dt.month && now.day == dt.day;
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final min = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    final time = '$hour:$min $ampm';
    if (isToday) return 'Today • $time';
    return '${dt.month}/${dt.day}/${dt.year} • $time';
  }

  Future<void> _openSystemSettings() async {
    await openAppSettings();
  }

  Future<void> _requestExactAlarmOnce() async {
    if (!Platform.isAndroid) return;
    final prefs = await SharedPreferences.getInstance();
    final shown = prefs.getBool('notif_exact_alarm_prompted') ?? false;
    if (shown) return;
    await prefs.setBool('notif_exact_alarm_prompted', true);
    const intent = AndroidIntent(
      action: 'android.settings.REQUEST_SCHEDULE_EXACT_ALARM',
    );
    try {
      await intent.launch();
    } catch (_) {
      // Ignore intent failures; user can still enable in settings manually.
    }
  }

  @override
  Widget build(BuildContext context) {
    final textSecondary = BracuPalette.textSecondary(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseBorderColor = BracuPalette.primary.withValues(
      alpha: isDark ? 0.35 : 0.18,
    );

    Color categoryColor(String category) {
      switch (category) {
        case 'class':
          return BracuPalette.primary;
        case 'exam':
          return const Color(0xFF7C56FF);
        case 'friend':
          return const Color(0xFF5B8DEF);
        case 'system':
          return const Color(0xFF2C9DFF);
        default:
          return BracuPalette.primary;
      }
    }

    IconData categoryIcon(String category) {
      switch (category) {
        case 'class':
          return Icons.alarm_outlined;
        case 'exam':
          return Icons.event_note_outlined;
        case 'friend':
          return Icons.people_outline;
        case 'system':
          return Icons.notifications_active_outlined;
        default:
          return Icons.notifications_none_outlined;
      }
    }

    return DefaultTabController(
      length: 2,
      child: BracuPageScaffold(
        title: 'Notifications',
        subtitle: 'Updates & Alerts',
        icon: Icons.notifications_none_outlined,
        actions: [
          IconButton(
            tooltip: 'System settings',
            onPressed: _openSystemSettings,
            icon: const Icon(Icons.settings_outlined),
            color: BracuPalette.primary,
          ),
        ],
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 10),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: BracuPalette.card(context),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: baseBorderColor),
                  boxShadow: isDark
                      ? const []
                      : [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.06),
                            blurRadius: 14,
                            offset: const Offset(0, 8),
                          ),
                        ],
                ),
                child: TabBar(
                  labelColor: Colors.white,
                  unselectedLabelColor: textSecondary,
                  indicatorSize: TabBarIndicatorSize.tab,
                  dividerColor: Colors.transparent,
                  indicator: BoxDecoration(
                    color: BracuPalette.primary,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  tabs: const [
                    Tab(text: 'All'),
                    Tab(text: 'Settings'),
                  ],
                ),
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  if (_loading)
                    const BracuLoading()
                  else if (_items.isEmpty)
                    const Center(
                      child: BracuEmptyState(message: 'No notifications yet.'),
                    )
                  else
                    ListView(
                      padding: const EdgeInsets.fromLTRB(20, 6, 20, 28),
                      children: [
                        ..._items.map(
                          (item) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Dismissible(
                              key: ValueKey(item.id),
                              direction: DismissDirection.endToStart,
                              background: Container(
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFFD63B3B,
                                  ).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.only(right: 16),
                                child: const Icon(
                                  Icons.delete_outline,
                                  color: Color(0xFFD63B3B),
                                ),
                              ),
                              onDismissed: (_) => _deleteNotification(item),
                              child: NotificationTile(
                                item: NotificationTileItem(
                                  title: item.title,
                                  message: item.message,
                                  time: _formatTime(item.timeIso),
                                  icon: categoryIcon(item.category),
                                  color: categoryColor(item.category),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ListView(
                    padding: const EdgeInsets.fromLTRB(20, 6, 20, 28),
                    children: [
                      const BracuSectionTitle(title: 'Push Alerts'),
                      const SizedBox(height: 10),
                      BracuCard(
                        child: Column(
                          children: [
                            SettingTile(
                              title: 'All Notifications',
                              subtitle: 'Master switch for everything.',
                              value: allEnabled,
                              onChanged: _toggleAll,
                            ),
                            const Divider(height: 1),
                            SettingTile(
                              title: 'Class Reminders',
                              subtitle: 'Time-based alerts before class.',
                              value: classReminders,
                              onChanged: (value) => _toggleSetting(
                                value,
                                (next) => classReminders = next,
                              ),
                            ),
                            const Divider(height: 1),
                            SettingTile(
                              title: 'Exam Updates',
                              subtitle: 'Notices about exam schedules.',
                              value: examUpdates,
                              onChanged: (value) => _toggleSetting(
                                value,
                                (next) => examUpdates = next,
                              ),
                            ),
                            const Divider(height: 1),
                            SettingTile(
                              title: 'Friend Schedules',
                              subtitle: 'Alerts for incoming shares.',
                              value: friendUpdates,
                              onChanged: (value) => _toggleSetting(
                                value,
                                (next) => friendUpdates = next,
                              ),
                            ),
                            const Divider(height: 1),
                            SettingTile(
                              title: 'System Alerts',
                              subtitle: 'Maintenance and security notices.',
                              value: systemAlerts,
                              onChanged: (value) => _toggleSetting(
                                value,
                                (next) => systemAlerts = next,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      const BracuSectionTitle(title: 'Delivery'),
                      const SizedBox(height: 10),
                      BracuCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Notifications are synced when you sign in or '
                              'refresh data. For the best experience, keep '
                              'the app running in background.',
                              style: TextStyle(color: textSecondary),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
