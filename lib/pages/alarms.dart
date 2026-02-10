import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:flutter_alarmkit/flutter_alarmkit.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:preconnect/api/bracu_auth_manager.dart';
import 'package:preconnect/model/section_info.dart';
import 'package:preconnect/pages/ui_kit.dart';

class AlarmPage extends StatefulWidget {
  const AlarmPage({super.key});

  @override
  State<AlarmPage> createState() => _AlarmPageState();
}

class _AlarmPageState extends State<AlarmPage> {
  late Future<List<Section>> _futureSections;
  final Map<String, int> _minutesBefore = {};

  @override
  void initState() {
    super.initState();
    unawaited(BracuAuthManager().fetchStudentSchedule());
    _futureSections = _fetchSchedule();
  }

  Future<List<Section>> _fetchSchedule({bool forceRefresh = false}) async {
    if (forceRefresh) {
      await BracuAuthManager().fetchStudentSchedule();
    } else {
      unawaited(BracuAuthManager().fetchStudentSchedule());
    }
    final jsonString = await BracuAuthManager().getStudentSchedule();
    if (jsonString == null || jsonString.trim().isEmpty) {
      return const [];
    }

    final decoded = jsonDecode(jsonString) as List<dynamic>;
    return decoded.map((e) => Section.fromJson(e)).toList();
  }

  Future<void> _handleRefresh() async {
    setState(() {
      _futureSections = _fetchSchedule(forceRefresh: true);
    });
    await _futureSections;
  }

  Future<void> _setAlarm(
    BuildContext context,
    List<String> days,
    String startTime,
    String courseCode,
    int minutesBefore,
  ) async {
    final timeParts = startTime.split(':');
    var hour = int.parse(timeParts[0]);
    var minute = int.parse(timeParts[1]);

    final classTime = DateTime(2025, 1, 2, hour, minute);
    final adjusted = classTime.subtract(Duration(minutes: minutesBefore));
    hour = adjusted.hour;
    minute = adjusted.minute;
    final dayShift = adjusted.day.compareTo(classTime.day);

    if (Platform.isIOS) {
      final weekdays = _mapWeekdays(days, shift: dayShift);
      if (weekdays.isEmpty) return;
      try {
        final alarmkit = FlutterAlarmkit();
        await alarmkit.getPlatformVersion();
        final authorized = await alarmkit.requestAuthorization();
        if (!authorized) {
          if (!context.mounted) return;
          _showThemedSnackBar(context, 'Alarm permission denied.');
          return;
        }
        await alarmkit.scheduleRecurrentAlarm(
          weekdays: weekdays,
          hour: hour,
          minute: minute,
          label: '$courseCode Class Reminder ($minutesBefore min before)',
          tintColor: '#1E6BE3',
        );
        if (!context.mounted) return;
        _showThemedSnackBar(context, 'Alarm scheduled on iOS.');
      } on PlatformException catch (e) {
        if (!context.mounted) return;
        _showThemedSnackBar(
          context,
          e.code == 'UNSUPPORTED'
              ? 'AlarmKit requires iOS 26+.'
              : 'Unable to schedule alarm on this iOS.',
        );
      } catch (_) {
        if (!context.mounted) return;
        _showThemedSnackBar(context, 'Unable to schedule alarm on this iOS.');
      }
      return;
    }

    final dayMapping = {
      'SUNDAY': 1,
      'MONDAY': 2,
      'TUESDAY': 3,
      'WEDNESDAY': 4,
      'THURSDAY': 5,
      'FRIDAY': 6,
      'SATURDAY': 7,
    };

    final alarmDays = days
        .map((day) => dayMapping[day])
        .whereType<int>()
        .toList();

    final intent = AndroidIntent(
      action: 'android.intent.action.SET_ALARM',
      arguments: {
        'android.intent.extra.alarm.HOUR': hour,
        'android.intent.extra.alarm.MINUTES': minute,
        'android.intent.extra.alarm.MESSAGE':
            '$courseCode Class Reminder ($minutesBefore min before)',
        'android.intent.extra.alarm.DAYS': alarmDays,
        'android.intent.extra.alarm.SKIP_UI': false,
      },
      flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
    );

    try {
      await intent.launch();
      if (!context.mounted) return;
      _showThemedSnackBar(context, 'Alarm opened in Clock app.');
    } catch (_) {
      if (!context.mounted) return;
      _showThemedSnackBar(context, 'Unable to open alarm on Android.');
    }
  }

  void _showThemedSnackBar(BuildContext context, String message) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(color: Colors.white),
        ),
        backgroundColor: isDark ? const Color(0xFF1E6BE3) : BracuPalette.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      ),
    );
  }

  Set<Weekday> _mapWeekdays(List<String> days, {int shift = 0}) {
    Weekday? toWeekday(String day) {
      switch (day.toUpperCase()) {
        case 'MONDAY':
          return Weekday.monday;
        case 'TUESDAY':
          return Weekday.tuesday;
        case 'WEDNESDAY':
          return Weekday.wednesday;
        case 'THURSDAY':
          return Weekday.thursday;
        case 'FRIDAY':
          return Weekday.friday;
        case 'SATURDAY':
          return Weekday.saturday;
        case 'SUNDAY':
          return Weekday.sunday;
        default:
          return null;
      }
    }

    Weekday shiftWeekday(Weekday day, int shiftBy) {
      final order = [
        Weekday.monday,
        Weekday.tuesday,
        Weekday.wednesday,
        Weekday.thursday,
        Weekday.friday,
        Weekday.saturday,
        Weekday.sunday,
      ];
      final index = order.indexOf(day);
      if (index < 0) return day;
      final next = (index + shiftBy) % order.length;
      return order[(next + order.length) % order.length];
    }

    final mapped = days.map(toWeekday).whereType<Weekday>().toSet();
    if (shift == 0) return mapped;
    return mapped.map((d) => shiftWeekday(d, shift)).toSet();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = BracuPalette.textPrimary(context);
    final textSecondary = BracuPalette.textSecondary(context);
    final chipBg = isDark
        ? const Color(0xFF0F3B6D)
        : BracuPalette.primary.withValues(alpha: 0.10);
    final controlBg = isDark ? const Color(0xFF0B0B0B) : Colors.white;

    return BracuPageScaffold(
      title: 'Set Alarms',
      subtitle: 'Class Reminders',
      icon: Icons.alarm_outlined,
      body: FutureBuilder<List<Section>>(
        future: _futureSections,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return RefreshIndicator(
              onRefresh: _handleRefresh,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 160),
                  BracuLoading(label: 'Loading classes...'),
                ],
              ),
            );
          }
          if (snapshot.hasError) {
            return RefreshIndicator(
              onRefresh: _handleRefresh,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  const SizedBox(height: 160),
                  BracuEmptyState(message: 'Error: ${snapshot.error}'),
                ],
              ),
            );
          }

          final sections = snapshot.data ?? [];
          if (sections.isEmpty) {
            return RefreshIndicator(
              onRefresh: _handleRefresh,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 160),
                  BracuEmptyState(message: 'No classes found'),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: _handleRefresh,
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: sections.length + 1,
              itemBuilder: (context, index) {
                if (index == sections.length) {
                  return const Padding(
                    padding: EdgeInsets.only(top: 12),
                  );
                }
                final section = sections[index];
                final schedules = section.sectionSchedule.classSchedules;
                if (schedules.isEmpty) return const SizedBox.shrink();

                final courseCode = section.courseCode;
                _minutesBefore.putIfAbsent(courseCode, () => 10);

                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: BracuCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: BracuPalette.primary.withValues(
                                  alpha: 0.12,
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                formatSectionBadge(section.sectionName),
                                style: const TextStyle(
                                  color: BracuPalette.primary,
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
                                    courseCode,
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Class alarms',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: schedules.map((s) {
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: chipBg,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '${s.day} • ${formatTimeRange(s.startTime, s.endTime)}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: textPrimary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: controlBg,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: BracuPalette.primary.withValues(
                                alpha: 0.2,
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              InkWell(
                                onTap: () {
                                  setState(() {
                                    if (_minutesBefore[courseCode]! > 5) {
                                      _minutesBefore[courseCode] =
                                          _minutesBefore[courseCode]! - 5;
                                    }
                                  });
                                },
                                borderRadius: BorderRadius.circular(10),
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: BracuPalette.primary.withValues(
                                      alpha: 0.12,
                                    ),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(
                                    Icons.remove,
                                    size: 18,
                                    color: BracuPalette.primary,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Center(
                                  child: Text(
                                    '${_minutesBefore[courseCode]} min before',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: textPrimary,
                                    ),
                                  ),
                                ),
                              ),
                              InkWell(
                                onTap: () {
                                  setState(() {
                                    _minutesBefore[courseCode] =
                                        _minutesBefore[courseCode]! + 5;
                                  });
                                },
                                borderRadius: BorderRadius.circular(10),
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: BracuPalette.primary.withValues(
                                      alpha: 0.12,
                                    ),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(
                                    Icons.add,
                                    size: 18,
                                    color: BracuPalette.primary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: BracuPalette.primary,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                ),
                                onPressed: () async {
                                  final days = schedules
                                      .map((s) => s.day)
                                      .toList();
                                  final startTime = schedules.isNotEmpty
                                      ? schedules.first.startTime
                                      : "";

                                  if (startTime.isNotEmpty && days.isNotEmpty) {
                                    await _setAlarm(
                                      context,
                                      days,
                                      startTime,
                                      courseCode,
                                      _minutesBefore[courseCode]!,
                                    );
                                  }
                                },
                                icon: const Icon(Icons.notifications_active),
                                label: const Text('Set Alarm'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
