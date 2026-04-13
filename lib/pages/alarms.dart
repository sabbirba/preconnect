import 'dart:async';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_alarmkit/flutter_alarmkit.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:preconnect/api/exam_map_service.dart';
import 'package:preconnect/api/schedule_service.dart';
import 'package:preconnect/model/section_info.dart';
import 'package:preconnect/pages/shared_widgets/schedule_entry_card.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/refresh_bus.dart';
import 'package:preconnect/tools/exam_sorting.dart';
import 'package:preconnect/tools/ramadan_timing.dart';
import 'package:preconnect/tools/time_utils.dart';

class AlarmPage extends StatefulWidget {
  const AlarmPage({super.key});

  @override
  State<AlarmPage> createState() => _AlarmPageState();
}

class _AlarmPageState extends State<AlarmPage> with RefreshBusState {
  static const MethodChannel _androidAlarmChannel = MethodChannel(
    'preconnect/android_alarm',
  );
  late Future<_AlarmData> _futureData;
  final Map<String, int> _minutesBefore = {};

  @override
  void initState() {
    super.initState();
    unawaited(ScheduleService().fetchStudentSchedule());
    _futureData = _fetchSchedule();
    bindRefreshBus(_onRefreshSignal);
  }

  @override
  void dispose() {
    unbindRefreshBus(_onRefreshSignal);
    super.dispose();
  }

  void _onRefreshSignal() {
    if (!mounted) return;
    if (isRefreshingFrom('alarms')) {
      return;
    }
    unawaited(_handleRefresh(notify: false));
  }

  Future<_AlarmData> _fetchSchedule({bool forceRefresh = false}) async {
    final ramadanFuture = RamadanTiming.isRamadan(forceRefresh: forceRefresh);
    final sections = await ScheduleService().getStudentSections(
      forceRefresh: forceRefresh,
    );
    final overrides = await ExamScheduleService().getOverridesForSections(
      sections,
      forceRefresh: forceRefresh,
    );
    final examEntries = _buildExamEntries(sections, overrides);
    if (sections.isEmpty) {
      final isRamadan = await ramadanFuture;
      return _AlarmData(
        sections: const [],
        examEntries: examEntries,
        isRamadan: isRamadan,
      );
    }

    final isRamadan = await ramadanFuture;
    return _AlarmData(
      sections: sections,
      examEntries: examEntries,
      isRamadan: isRamadan,
    );
  }

  List<_ExamAlarmEntry> _buildExamEntries(
    List<Section> sections,
    Map<String, ExamScheduleOverride> overrides,
  ) {
    final service = ExamScheduleService();
    final now = DateTime.now();
    final items = <_ExamAlarmEntry>[];
    for (final section in sections) {
      final resolved = service.resolveSection(
        section: section,
        overrides: overrides,
      );
      final midAt = BracuTime.parseDateTime(
        resolved.midDate,
        resolved.midStartTime,
      );
      if (midAt != null && !midAt.isBefore(now)) {
        items.add(
          _ExamAlarmEntry(
            id: '${section.sectionId}-mid',
            type: 'Midterm',
            courseCode: section.courseCode,
            sectionName: section.sectionName,
            roomNumber: resolved.midRoomNumber ?? '',
            faculties: section.faculties,
            consumedSeat: section.consumedSeat,
            startTime: resolved.midStartTime,
            endTime: resolved.midEndTime,
            dateTime: midAt,
          ),
        );
      }
      final finalAt = BracuTime.parseDateTime(
        resolved.finalDate,
        resolved.finalStartTime,
      );
      if (finalAt != null && !finalAt.isBefore(now)) {
        items.add(
          _ExamAlarmEntry(
            id: '${section.sectionId}-final',
            type: 'Final',
            courseCode: section.courseCode,
            sectionName: section.sectionName,
            roomNumber: resolved.finalRoomNumber ?? '',
            faculties: section.faculties,
            consumedSeat: section.consumedSeat,
            startTime: resolved.finalStartTime,
            endTime: resolved.finalEndTime,
            dateTime: finalAt,
          ),
        );
      }
    }
    items.sort((a, b) {
      return ExamSorting.compareExamEntries(
        typeA: a.type,
        typeB: b.type,
        dateTimeA: a.dateTime,
        dateTimeB: b.dateTime,
        courseCodeA: a.courseCode,
        courseCodeB: b.courseCode,
        sectionNameA: a.sectionName,
        sectionNameB: b.sectionName,
      );
    });
    return items;
  }

  Future<void> _handleRefresh({bool notify = true}) async {
    if (!await ensureOnline(context, notify: notify)) {
      return;
    }
    setState(() {
      _futureData = _fetchSchedule(forceRefresh: true);
    });
    await _futureData;
  }

  Future<void> _setAlarm(
    BuildContext context,
    List<String> days,
    String startTime,
    String courseCode,
    int minutesBefore,
  ) async {
    if (kIsWeb) {
      if (!context.mounted) return;
      showAppSnackBar(context, 'Alarm setup is not available on web.');
      return;
    }
    final parsed = BracuTime.parseHourMinute(startTime);
    if (parsed == null) {
      if (!context.mounted) return;
      showAppSnackBar(context, 'Unable to parse class time.');
      return;
    }
    var (hour, minute) = parsed;

    final classTime = DateTime(2025, 1, 2, hour, minute);
    final adjusted = classTime.subtract(Duration(minutes: minutesBefore));
    hour = adjusted.hour;
    minute = adjusted.minute;
    final dayShift = adjusted.day.compareTo(classTime.day);

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final weekdays = _mapWeekdays(days, shift: dayShift);
      if (weekdays.isEmpty) return;
      try {
        final alarmkit = FlutterAlarmkit();
        await alarmkit.getPlatformVersion();
        final authorized = await alarmkit.requestAuthorization();
        if (!authorized) {
          if (!context.mounted) return;
          showAppSnackBar(context, 'Alarm permission denied.');
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
        showAppSnackBar(context, 'Alarm scheduled on iOS.');
        RefreshBus.instance.notify(reason: 'alarms');
      } on PlatformException catch (e) {
        if (!context.mounted) return;
        showAppSnackBar(
          context,
          e.code == 'UNSUPPORTED'
              ? 'AlarmKit requires iOS 26+.'
              : 'Unable to schedule alarm on this iOS.',
        );
      } catch (_) {
        if (!context.mounted) return;
        showAppSnackBar(context, 'Unable to schedule alarm on this iOS.');
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

    try {
      final opened = await _androidAlarmChannel.invokeMethod<bool>(
        'setAlarm',
        {
          'hour': hour,
          'minute': minute,
          'message': '$courseCode Class Reminder ($minutesBefore min before)',
          'days': alarmDays,
        },
      );
      if (opened != true) {
        throw Exception('Unable to open alarm on Android.');
      }
      if (!context.mounted) return;
      showAppSnackBar(context, 'Alarm opened in Clock app.');
      RefreshBus.instance.notify(reason: 'alarms');
    } catch (_) {
      if (!context.mounted) return;
      showAppSnackBar(context, 'Unable to open alarm on Android.');
    }
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

  Future<void> _setExamAlarm(
    BuildContext context,
    _ExamAlarmEntry entry,
    int minutesBefore,
  ) async {
    if (kIsWeb) {
      if (!context.mounted) return;
      showAppSnackBar(context, 'Alarm setup is not available on web.');
      return;
    }

    final fireAt = entry.dateTime.subtract(Duration(minutes: minutesBefore));
    if (fireAt.isBefore(DateTime.now())) {
      if (!context.mounted) return;
      showAppSnackBar(context, 'This exam is already over.');
      return;
    }

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      try {
        final alarmkit = FlutterAlarmkit();
        await alarmkit.getPlatformVersion();
        final authorized = await alarmkit.requestAuthorization();
        if (!authorized) {
          if (!context.mounted) return;
          showAppSnackBar(context, 'Alarm permission denied.');
          return;
        }
        await alarmkit.scheduleOneShotAlarm(
          timestamp: fireAt.millisecondsSinceEpoch.toDouble(),
          label:
              '${entry.courseCode} ${entry.type} Reminder ($minutesBefore min before)',
          tintColor: '#1E6BE3',
        );
        if (!context.mounted) return;
        showAppSnackBar(context, 'Exam alarm scheduled on iOS.');
        RefreshBus.instance.notify(reason: 'alarms');
      } on PlatformException catch (e) {
        if (!context.mounted) return;
        showAppSnackBar(
          context,
          e.code == 'UNSUPPORTED'
              ? 'AlarmKit requires iOS 26+.'
              : 'Unable to schedule exam alarm on this iOS.',
        );
      } catch (_) {
        if (!context.mounted) return;
        showAppSnackBar(context, 'Unable to schedule exam alarm on this iOS.');
      }
      return;
    }

    try {
      final opened = await _androidAlarmChannel.invokeMethod<bool>(
        'setAlarm',
        {
          'hour': fireAt.hour,
          'minute': fireAt.minute,
          'message':
              '${entry.courseCode} ${entry.type} Reminder ($minutesBefore min before)',
        },
      );
      if (opened != true) {
        throw Exception('Unable to open alarm on Android.');
      }
      if (!context.mounted) return;
      showAppSnackBar(
        context,
        'Alarm opened in Clock app. Please verify the date and time.',
      );
      RefreshBus.instance.notify(reason: 'alarms');
    } catch (_) {
      if (!context.mounted) return;
      showAppSnackBar(context, 'Unable to open alarm on Android.');
    }
  }

  String _formatExamDateOnly(DateTime dt) {
    return DateFormat('d MMMM, yyyy').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final chipBg = isDark
        ? const Color(0xFF0F3B6D)
        : BracuPalette.primary.withValues(alpha: 0.10);
    final controlBg = isDark ? const Color(0xFF0B0B0B) : Colors.white;

    return BracuPageScaffold(
      title: 'Set Alarms',
      subtitle: 'Class & Exam',
      icon: Icons.alarm_outlined,
      body: FutureBuilder<_AlarmData>(
        future: _futureData,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return buildRefreshLoadingState(
              onRefresh: _handleRefresh,
              label: 'Loading...',
            );
          }
          if (snapshot.hasError) {
            return buildRefreshErrorState(
              onRefresh: _handleRefresh,
              error: snapshot.error,
            );
          }

          final sections = snapshot.data?.sections ?? const <Section>[];
          final exams = snapshot.data?.examEntries ?? const <_ExamAlarmEntry>[];
          final isRamadan = snapshot.data?.isRamadan ?? false;
          if (sections.isEmpty && exams.isEmpty) {
            return buildRefreshEmptyState(
              onRefresh: _handleRefresh,
              message: 'No class or exam found',
            );
          }

          return BracuRefreshListBuilder(
            onRefresh: _handleRefresh,
            itemCount: sections.length + exams.length + 2,
            itemBuilder: (context, index) {
              if (index == sections.length + exams.length + 1) {
                return const Padding(padding: EdgeInsets.only(top: 12));
              }
              if (index == sections.length && exams.isNotEmpty) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12, top: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Divider(
                        height: 1,
                        thickness: 1,
                        color: BracuPalette.primary.withValues(alpha: 0.38),
                      ),
                    ],
                  ),
                );
              }

              if (index > sections.length && exams.isNotEmpty) {
                final examIndex = index - sections.length - 1;
                final exam = exams[examIndex];
                final showTypeHeader =
                    examIndex == 0 || exams[examIndex - 1].type != exam.type;
                final alarmKey = 'exam_${exam.id}';
                _minutesBefore.putIfAbsent(alarmKey, () => 15);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (showTypeHeader && exam.type == 'Final')
                        const SizedBox(height: 8),
                      BracuCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                SectionBadge(
                                  label: formatSectionBadge(exam.sectionName),
                                  color: exam.type == 'Final'
                                      ? BracuPalette.accent
                                      : BracuPalette.primary,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text.rich(
                                        TextSpan(
                                          children: [
                                            TextSpan(
                                              text: exam.courseCode.trim(),
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            TextSpan(
                                              text: ' ${exam.type}',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w600,
                                                color:
                                                    BracuPalette.textSecondary(
                                                      context,
                                                    ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        formatTimeRange(
                                          exam.startTime,
                                          exam.endTime,
                                        ),
                                        style: TextStyle(
                                          color: BracuPalette.textPrimary(
                                            context,
                                          ),
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      exam.roomNumber.trim().isEmpty
                                          ? 'TBA'
                                          : exam.roomNumber,
                                      style: TextStyle(
                                        color: BracuPalette.textPrimary(
                                          context,
                                        ),
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    if (exam.faculties.trim().isNotEmpty ||
                                        exam.consumedSeat > 0) ...[
                                      const SizedBox(height: 2),
                                      Text.rich(
                                        TextSpan(
                                          children: [
                                            if (exam.faculties
                                                .trim()
                                                .isNotEmpty)
                                              TextSpan(
                                                text: exam.faculties.trim(),
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w700,
                                                  color:
                                                      BracuPalette.textPrimary(
                                                        context,
                                                      ),
                                                ),
                                              ),
                                            if (exam.consumedSeat > 0)
                                              TextSpan(
                                                text:
                                                    '${exam.faculties.trim().isEmpty ? '' : ' '}(${exam.consumedSeat})',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color:
                                                      BracuPalette.textSecondary(
                                                        context,
                                                      ),
                                                ),
                                              ),
                                          ],
                                        ),
                                        textAlign: TextAlign.right,
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: Wrap(
                                alignment: WrapAlignment.center,
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: chipBg,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      _formatExamDateOnly(exam.dateTime),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: BracuPalette.textPrimary(
                                          context,
                                        ),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: chipBg,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      DateFormat(
                                        'EEEE',
                                      ).format(exam.dateTime).toUpperCase(),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: BracuPalette.textPrimary(
                                          context,
                                        ),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
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
                                        if (_minutesBefore[alarmKey]! > 5) {
                                          _minutesBefore[alarmKey] =
                                              _minutesBefore[alarmKey]! - 5;
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
                                        '${_minutesBefore[alarmKey]} min before',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          color: BracuPalette.textPrimary(
                                            context,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  InkWell(
                                    onTap: () {
                                      setState(() {
                                        _minutesBefore[alarmKey] =
                                            _minutesBefore[alarmKey]! + 5;
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
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                style: bracuCompactPrimaryButtonStyle(),
                                onPressed: () async {
                                  await _setExamAlarm(
                                    context,
                                    exam,
                                    _minutesBefore[alarmKey]!,
                                  );
                                },
                                icon: const Icon(Icons.notifications_active),
                                label: const Text('Set Alarm'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }

              final section = sections[index];
              final schedules = section.sectionSchedule.classSchedules;
              if (schedules.isEmpty) return const SizedBox.shrink();

              final courseCode = section.courseCode;
              _minutesBefore.putIfAbsent(courseCode, () => 5);
              final schedule = schedules.first;

              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: BracuCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ScheduleEntryCard(
                        sectionName: section.sectionName,
                        courseCode: courseCode,
                        schedule: schedule,
                        isRamadan: isRamadan,
                        roomNumber: section.roomNumber,
                        faculties: section.faculties,
                        consumedSeat: section.consumedSeat,
                        courseType: section.courseType,
                        wrapInCard: false,
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: Wrap(
                          alignment: WrapAlignment.center,
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
                                s.day.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: BracuPalette.textPrimary(context),
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                softWrap: false,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                              ),
                            );
                          }).toList(),
                        ),
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
                            color: BracuPalette.primary.withValues(alpha: 0.2),
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
                                    color: BracuPalette.textPrimary(context),
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
                                    ? RamadanTiming.adjustRange(
                                        schedules.first.startTime,
                                        schedules.first.endTime,
                                        isRamadan: isRamadan,
                                      ).startTime
                                    : '';

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
          );
        },
      ),
    );
  }
}

class _AlarmData {
  const _AlarmData({
    required this.sections,
    required this.examEntries,
    required this.isRamadan,
  });

  final List<Section> sections;
  final List<_ExamAlarmEntry> examEntries;
  final bool isRamadan;
}

class _ExamAlarmEntry {
  const _ExamAlarmEntry({
    required this.id,
    required this.type,
    required this.courseCode,
    required this.sectionName,
    required this.roomNumber,
    required this.faculties,
    required this.consumedSeat,
    required this.startTime,
    required this.endTime,
    required this.dateTime,
  });

  final String id;
  final String type;
  final String courseCode;
  final String sectionName;
  final String roomNumber;
  final String faculties;
  final int consumedSeat;
  final String? startTime;
  final String? endTime;
  final DateTime dateTime;
}
