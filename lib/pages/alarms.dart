import 'dart:async';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:preconnect/tools/calendar_event.dart';
import 'package:intl/intl.dart';
import 'package:preconnect/api/exam_map.dart';
import 'package:preconnect/api/schedule.dart';
import 'package:preconnect/api/custom_schedules.dart';
import 'package:preconnect/model/section_info.dart';
import 'package:preconnect/model/custom_schedule.dart';
import 'package:preconnect/features/schedule/application/session_resolver.dart';
import 'package:preconnect/pages/shared_widgets/scroll_helper.dart';
import 'package:preconnect/pages/shared_widgets/exam_filter.dart';
import 'package:preconnect/pages/shared_widgets/entry_card.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/pages/custom_schedules_sections/schedules_shared.dart';
import 'package:preconnect/api/profile.dart';
import 'package:preconnect/tools/snapshot_store.dart';
import 'package:preconnect/tools/preload_cache.dart';
import 'package:preconnect/tools/storage_keys.dart';
import 'package:preconnect/tools/refresh_bus.dart';
import 'package:preconnect/pages/shared_widgets/online_guard.dart';
import 'package:preconnect/tools/string_utils.dart';
import 'package:preconnect/tools/exam_visibility.dart';
import 'package:preconnect/tools/ramadan.dart';
import 'package:preconnect/tools/time_utils.dart';
import 'package:preconnect/tools/app_storage.dart';
import 'package:preconnect/tools/android_alarm.dart';

part 'alarm_sections/alarm_models.dart';

class AlarmPage extends StatefulWidget {
  const AlarmPage({super.key});

  static Future<void> preload() async {
    await _AlarmPageState.preloadData();
  }

  @override
  State<AlarmPage> createState() => _AlarmPageState();
}

class _AlarmPageState extends State<AlarmPage> with RefreshBusState {
  static final CachedPageController<_AlarmData> cache =
      CachedPageController<_AlarmData>(
        ({bool forceRefresh = false}) =>
            _loadAlarmData(forceRefresh: forceRefresh),
      );

  late Future<_AlarmData> _futureData;
  _AlarmData? _latestData;
  final ScrollController _scrollController = ScrollController();
  late final HighlightScrollCoordinator _highlightScroll =
      HighlightScrollCoordinator(scrollController: _scrollController);
  final Map<String, int> _minutesBefore = {};
  bool _showDoneAlarms = false;
  List<Section>? _courseOptionsForSections;
  List<CustomSchedulesCourseOption>? _courseOptionsCache;

  @override
  void initState() {
    super.initState();
    _latestData = cache.value;
    _futureData = cache.value == null
        ? _fetchSchedule()
        : Future<_AlarmData>.value(cache.value!);
    cache.addListener(_onCacheUpdated);
    bindRefreshBus(_onRefreshSignal);
    unawaited(_warmAndBind());
  }

  @override
  void dispose() {
    cache.removeListener(_onCacheUpdated);
    unbindRefreshBus(_onRefreshSignal);
    _scrollController.dispose();
    super.dispose();
  }

  void _onCacheUpdated() {
    if (!mounted) return;
    final val = cache.value;
    if (val != null) {
      setState(() {
        _latestData = val;
        _futureData = Future<_AlarmData>.value(val);
      });
    }
  }

  void _onRefreshSignal() {
    if (!mounted) return;
    if (isRefreshingFrom('alarms')) {
      return;
    }
    if (isRefreshingFrom('cache_cleared')) {
      unawaited(_handleRefresh(notify: false));
      return;
    }
    unawaited(_handleRefresh(notify: false));
  }

  Future<void> _warmAndBind() async {
    final data = await preloadData();
    if (!mounted) return;
    setState(() {
      _latestData = data;
      _futureData = Future<_AlarmData>.value(data);
    });
  }

  static Future<_AlarmData> preloadData({bool forceRefresh = false}) async {
    return cache.load(forceRefresh: forceRefresh);
  }

  Future<_AlarmData> _fetchSchedule({bool forceRefresh = false}) async {
    return preloadData(forceRefresh: forceRefresh);
  }

  static Future<_AlarmData> _loadAlarmData({bool forceRefresh = false}) async {
    if (!forceRefresh) {
      final cached = await JsonSnapshotStore.read<_AlarmData>(
        key: StorageKeys.alarmsSnapshot,
        decode: (decoded) {
          final sectionsRaw = decoded['sections'];
          final examsRaw = decoded['examEntries'];
          final isRamadan = decoded['isRamadan'] == true;
          final customRaw = decoded['customSchedules'];
          final advisingRaw = decoded['advisingInfo'];
          final advisingInfo = advisingRaw is Map
              ? advisingRaw.map((k, v) => MapEntry('$k', v?.toString()))
              : null;
          if (sectionsRaw is! List || examsRaw is! List) return null;
          final sections = sectionsRaw
              .whereType<Map>()
              .map((entry) => Section.fromJson(entry.cast<String, dynamic>()))
              .toList(growable: false);
          final examEntries = examsRaw
              .whereType<Map>()
              .map(
                (entry) =>
                    _ExamAlarmEntry.fromJson(entry.cast<String, dynamic>()),
              )
              .toList(growable: false);
          final customSchedules = customRaw is List
              ? customRaw
                    .whereType<Map>()
                    .map(
                      (entry) => CustomSchedule.fromJson(
                        entry.cast<String, dynamic>(),
                      ),
                    )
                    .toList(growable: false)
              : const <CustomSchedule>[];
          return _AlarmData(
            sections: sections,
            examEntries: examEntries,
            isRamadan: isRamadan,
            customSchedules: customSchedules,
            advisingInfo: advisingInfo,
          );
        },
      );
      if (cached != null) {
        return cached;
      }
    }
    final advisingFuture = AdvisingService().getAdvisingInfo(
      fromFetch: forceRefresh,
    );
    final ramadanFuture = RamadanTiming.isRamadan(forceRefresh: forceRefresh);
    final customSchedules = await CustomSchedulesService()
        .getItems(forceRefresh: forceRefresh)
        .catchError((e) => const <CustomSchedule>[]);
    final semesterSessionId = await resolveCurrentSessionSemesterIdWithRetry();
    if (semesterSessionId == null) {
      final isRamadan = await ramadanFuture;
      final advisingInfo = await advisingFuture;
      return _AlarmData(
        sections: const [],
        examEntries: const <_ExamAlarmEntry>[],
        isRamadan: isRamadan,
        customSchedules: customSchedules,
        advisingInfo: advisingInfo,
      );
    }
    final sections = await ScheduleService().getUnifiedStudentSchedule(
      semesterSessionId: semesterSessionId,
      forceRefresh: forceRefresh,
    );
    final overrides = await ExamScheduleService().getOverridesForSections(
      sections,
      forceRefresh: forceRefresh,
    );
    final examEntries = _buildExamEntries(sections, overrides);
    final isRamadan = await ramadanFuture;
    final advisingInfo = await advisingFuture;
    final data = _AlarmData(
      sections: sections,
      examEntries: examEntries,
      isRamadan: isRamadan,
      customSchedules: customSchedules,
      advisingInfo: advisingInfo,
      examOverrides: overrides,
    );
    cache.value = data;
    await _writeSnapshot(data);
    return data;
  }

  static Future<void> _writeSnapshot(_AlarmData data) {
    return JsonSnapshotStore.write(
      key: StorageKeys.alarmsSnapshot,
      value: _alarmSnapshotPayload(data),
    );
  }

  static Map<String, dynamic> _alarmSnapshotPayload(_AlarmData data) {
    return <String, dynamic>{
      'sections': data.sections.map((section) => section.toJson()).toList(),
      'examEntries': data.examEntries.map((entry) => entry.toJson()).toList(),
      'isRamadan': data.isRamadan,
      'customSchedules': data.customSchedules
          .map((item) => item.toJson())
          .toList(),
      'advisingInfo': data.advisingInfo,
    };
  }

  static List<_ExamAlarmEntry> _buildExamEntries(
    List<Section> sections,
    Map<String, ExamScheduleOverride> overrides,
  ) {
    final service = ExamScheduleService();
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
      if (midAt != null) {
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
      if (finalAt != null) {
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

  String? _resolveHighlightedExamKey(List<_ExamAlarmEntry> exams) {
    final now = DateTime.now();
    DateTime? nextExamTime;
    String? nextExamKey;

    for (final exam in exams) {
      final startTime = exam.dateTime;
      if (startTime.isAfter(now)) {
        if (nextExamTime == null || startTime.isBefore(nextExamTime)) {
          nextExamTime = startTime;
          nextExamKey = exam.id;
        }
      }
    }

    return nextExamKey;
  }

  Future<void> _handleRefresh({bool notify = true}) async {
    if (!await ensureOnline(context, notify: notify)) {
      return;
    }
    if (!mounted) return;
    setState(() {
      _latestData = _latestData ?? cache.value;
      _futureData = preloadData(forceRefresh: true);
    });
    final data = await _futureData;
    if (mounted) {
      setState(() {
        _latestData = data;
      });
    }
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
        final now = DateTime.now();
        var addedAny = false;
        for (final targetWeekday in weekdays) {
          DateTime nextDate = DateTime(
            now.year,
            now.month,
            now.day,
            hour,
            minute,
          );
          while (nextDate.weekday != targetWeekday || nextDate.isBefore(now)) {
            nextDate = nextDate.add(const Duration(days: 1));
          }
          final event = Event(
            title: '$courseCode Class Reminder',
            description:
                '$courseCode Class Reminder ($minutesBefore min before)',
            location: 'BRACU Campus',
            startDate: nextDate,
            endDate: nextDate.add(const Duration(hours: 1)),
            recurrence: Recurrence(frequency: Frequency.weekly),
          );
          final success = await Add2Reminder.addReminder(event);
          if (success) addedAny = true;
        }
        if (addedAny) {
          if (!context.mounted) return;
          showAppSnackBar(context, 'Reminders added to Apple Reminders.');
          await AppStorage.instance.setBool('alarm_done_$courseCode', true);
          if (mounted) setState(() {});
          RefreshBus.instance.notify(reason: 'alarms');
        } else {
          if (!context.mounted) return;
          showAppSnackBar(
            context,
            'Unable to add reminders to Apple Reminders.',
          );
        }
      } catch (_) {
        if (!context.mounted) return;
        showAppSnackBar(context, 'Unable to add reminders to Apple Reminders.');
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
      final opened = await AndroidAlarm.set(
        hour: hour,
        minute: minute,
        message: '$courseCode Class Reminder ($minutesBefore min before)',
        days: alarmDays,
      );
      if (opened != true) {
        throw Exception('Unable to open alarm on Android.');
      }
      if (!context.mounted) return;
      showAppSnackBar(context, 'Alarm opened in Clock app.');
      await AppStorage.instance.setBool('alarm_done_$courseCode', true);
      if (mounted) setState(() {});
      RefreshBus.instance.notify(reason: 'alarms');
    } catch (_) {
      if (!context.mounted) return;
      showAppSnackBar(context, 'Unable to open alarm on Android.');
    }
  }

  Set<int> _mapWeekdays(List<String> days, {int shift = 0}) {
    final mapped = days.map(BracuTime.weekdayFromName).whereType<int>().toSet();
    if (shift == 0) return mapped;
    return mapped.map((day) => BracuTime.shiftWeekday(day, shift)).toSet();
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

    final alarmKey = 'exam_${entry.id}';

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      try {
        final event = Event(
          title: '${entry.courseCode} ${entry.type} Reminder',
          description:
              '${entry.courseCode} ${entry.type} Reminder ($minutesBefore min before)',
          location: 'BRACU Campus',
          startDate: fireAt,
          endDate: fireAt.add(const Duration(hours: 1)),
        );
        final success = await Add2Reminder.addReminder(event);
        if (success) {
          if (!context.mounted) return;
          showAppSnackBar(context, 'Reminder added to Apple Reminders.');
          await AppStorage.instance.setBool('alarm_done_$alarmKey', true);
          if (mounted) setState(() {});
          RefreshBus.instance.notify(reason: 'alarms');
        } else {
          if (!context.mounted) return;
          showAppSnackBar(
            context,
            'Unable to add reminder to Apple Reminders.',
          );
        }
      } catch (_) {
        if (!context.mounted) return;
        showAppSnackBar(context, 'Unable to add reminder to Apple Reminders.');
      }
      return;
    }

    try {
      final opened = await AndroidAlarm.set(
        hour: fireAt.hour,
        minute: fireAt.minute,
        message:
            '${entry.courseCode} ${entry.type} Reminder ($minutesBefore min before)',
      );
      if (opened != true) {
        throw Exception('Unable to open alarm on Android.');
      }
      if (!context.mounted) return;
      showAppSnackBar(
        context,
        'Alarm opened in Clock app. Please verify the date and time.',
      );
      await AppStorage.instance.setBool('alarm_done_$alarmKey', true);
      if (mounted) setState(() {});
      RefreshBus.instance.notify(reason: 'alarms');
    } catch (_) {
      if (!context.mounted) return;
      showAppSnackBar(context, 'Unable to open alarm on Android.');
    }
  }

  Future<void> _setCustomScheduleAlarm(
    BuildContext context,
    CustomSchedule item,
    int minutesBefore,
  ) async {
    if (kIsWeb) {
      if (!context.mounted) return;
      showAppSnackBar(context, 'Alarm setup is not available on web.');
      return;
    }

    final fireAt = item.startTime.subtract(Duration(minutes: minutesBefore));
    if (fireAt.isBefore(DateTime.now())) {
      if (!context.mounted) return;
      showAppSnackBar(context, 'This event is already over.');
      return;
    }

    final alarmKey = 'custom_${item.itemId}';

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      try {
        final event = Event(
          title: item.title,
          description: '${item.title} Reminder ($minutesBefore min before)',
          location: 'BRACU Campus',
          startDate: fireAt,
          endDate: fireAt.add(const Duration(hours: 1)),
        );
        final success = await Add2Reminder.addReminder(event);
        if (success) {
          if (!context.mounted) return;
          showAppSnackBar(context, 'Reminder added to Apple Reminders.');
          await AppStorage.instance.setBool('alarm_done_$alarmKey', true);
          if (mounted) setState(() {});
          RefreshBus.instance.notify(reason: 'alarms');
        } else {
          if (!context.mounted) return;
          showAppSnackBar(
            context,
            'Unable to add reminder to Apple Reminders.',
          );
        }
      } catch (_) {
        if (!context.mounted) return;
        showAppSnackBar(context, 'Unable to add reminder to Apple Reminders.');
      }
      return;
    }

    try {
      final opened = await AndroidAlarm.set(
        hour: fireAt.hour,
        minute: fireAt.minute,
        message: '${item.title} Reminder ($minutesBefore min before)',
        days: const <int>[],
      );
      if (opened != true) {
        throw Exception('Unable to open alarm on Android.');
      }
      if (!context.mounted) return;
      showAppSnackBar(
        context,
        'Alarm opened in Clock app. Please verify the date and time.',
      );
      await AppStorage.instance.setBool('alarm_done_$alarmKey', true);
      if (mounted) setState(() {});
      RefreshBus.instance.notify(reason: 'alarms');
    } catch (_) {
      if (!context.mounted) return;
      showAppSnackBar(context, 'Unable to open alarm on Android.');
    }
  }

  List<CustomSchedulesCourseOption> _courseOptionsFor(List<Section> sections) {
    final cached = _courseOptionsCache;
    if (cached != null && identical(_courseOptionsForSections, sections)) {
      return cached;
    }
    final courseOptions = <CustomSchedulesCourseOption>[];
    final seenOptions = <String>{};
    for (final sectionItem in sections) {
      final code = sectionItem.courseCode.trim().toUpperCase();
      if (code.isEmpty) continue;
      final option = (
        courseCode: code,
        sectionName: sectionItem.sectionName.trim(),
        classSchedules: sectionItem.sectionSchedule.classSchedules
            .map(
              (schedule) => (
                day: schedule.day,
                startTime: schedule.startTime,
                endTime: schedule.endTime,
              ),
            )
            .toList(),
      );
      if (seenOptions.add('${option.courseCode}|${option.sectionName}')) {
        courseOptions.add(option);
      }
    }
    _courseOptionsForSections = sections;
    _courseOptionsCache = courseOptions;
    return courseOptions;
  }

  bool _isAdvisingActive(Map<String, String?>? advisingInfo) {
    if (advisingInfo == null) return false;
    final startDate = DateTime.tryParse(
      advisingInfo['advisingStartDate'] ?? '',
    );
    final endDate = DateTime.tryParse(advisingInfo['advisingEndDate'] ?? '');
    if (startDate == null || endDate == null) return false;
    return !DateTime.now().isAfter(endDate);
  }

  Future<void> _setAdvisingAlarm(
    BuildContext context,
    String title,
    DateTime startTime,
    int minutesBefore,
  ) async {
    if (kIsWeb) {
      if (!context.mounted) return;
      showAppSnackBar(context, 'Alarm setup is not available on web.');
      return;
    }

    final fireAt = startTime.subtract(Duration(minutes: minutesBefore));
    if (fireAt.isBefore(DateTime.now())) {
      if (!context.mounted) return;
      showAppSnackBar(context, 'This event is already over.');
      return;
    }

    final alarmKey = 'advising_${startTime.millisecondsSinceEpoch}';

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      try {
        final event = Event(
          title: title,
          description: '$title Reminder ($minutesBefore min before)',
          location: 'BRACU Campus',
          startDate: fireAt,
          endDate: fireAt.add(const Duration(hours: 1)),
        );
        final success = await Add2Reminder.addReminder(event);
        if (success) {
          if (!context.mounted) return;
          showAppSnackBar(context, 'Reminder added to Apple Reminders.');
          await AppStorage.instance.setBool('alarm_done_$alarmKey', true);
          if (mounted) setState(() {});
          RefreshBus.instance.notify(reason: 'alarms');
        } else {
          if (!context.mounted) return;
          showAppSnackBar(
            context,
            'Unable to add reminder to Apple Reminders.',
          );
        }
      } catch (_) {
        if (!context.mounted) return;
        showAppSnackBar(context, 'Unable to add reminder to Apple Reminders.');
      }
      return;
    }

    try {
      final opened = await AndroidAlarm.set(
        hour: fireAt.hour,
        minute: fireAt.minute,
        message: '$title Reminder ($minutesBefore min before)',
        days: const <int>[],
      );
      if (opened != true) {
        throw Exception('Unable to open alarm on Android.');
      }
      if (!context.mounted) return;
      showAppSnackBar(
        context,
        'Alarm opened in Clock app. Please verify the date and time.',
      );
      await AppStorage.instance.setBool('alarm_done_$alarmKey', true);
      if (mounted) setState(() {});
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
    final chipBg = Colors.transparent;
    final controlBg = isDark ? const Color(0xFF0B0B0B) : Colors.white;

    return BracuPageScaffold(
      title: 'Set Alarms',
      subtitle: 'Class & Exam',
      icon: Icons.alarm_outlined,
      actions: [
        BracuSelectChip(
          icon: Icons.history_rounded,
          selected: _showDoneAlarms,
          compact: true,
          showArrow: false,
          showBorder: false,
          onTap: () {
            setState(() {
              _showDoneAlarms = !_showDoneAlarms;
              _highlightScroll.resetScrollState();
            });
          },
        ),
      ],
      body: FutureBuilder<_AlarmData>(
        future: _futureData,
        builder: (context, snapshot) {
          if (snapshot.hasError && _latestData == null) {
            return buildRefreshErrorState(
              onRefresh: _handleRefresh,
              error: snapshot.error,
            );
          }

          final data = _latestData ?? snapshot.data;
          if (snapshot.connectionState == ConnectionState.waiting &&
              data == null) {
            return buildRefreshLoadingState(onRefresh: _handleRefresh);
          }
          final sections = data?.sections ?? const <Section>[];
          final exams = data?.examEntries ?? const <_ExamAlarmEntry>[];
          final custom = data?.customSchedules ?? const <CustomSchedule>[];
          final isRamadan = data?.isRamadan ?? false;
          final courseOptions = _courseOptionsFor(sections);
          final advisingInfo = data?.advisingInfo;
          final advisingActive = _isAdvisingActive(advisingInfo);

          final advisingEndDate = advisingInfo != null
              ? DateTime.tryParse(advisingInfo['advisingEndDate'] ?? '')
              : null;
          final advisingIsPassed =
              advisingEndDate != null &&
              advisingEndDate.isBefore(DateTime.now());
          final showAdvisingSingle =
              advisingActive &&
              (_showDoneAlarms ? advisingIsPassed : !advisingIsPassed);

          final now = DateTime.now();
          final filteredCustom = custom.where((item) {
            final isPassed = item.endTime != null
                ? item.endTime!.isBefore(now)
                : item.startTime.isBefore(now);
            return _showDoneAlarms ? isPassed : !isPassed;
          }).toList();

          final filteredExams = exams.where((exam) {
            return _showDoneAlarms ? exam.isPassed : !exam.isPassed;
          }).toList();

          final filteredSections = sections.where((section) {
            final isDone = CourseSectionExamFilter.isFinishedAfterFinalExam(
              section: section,
              overrides: data?.examOverrides ?? const {},
            );
            return _showDoneAlarms ? isDone : !isDone;
          }).toList();

          if (!showAdvisingSingle &&
              filteredCustom.isEmpty &&
              filteredSections.isEmpty &&
              filteredExams.isEmpty) {
            if (!_showDoneAlarms &&
                sections.isEmpty &&
                exams.isEmpty &&
                custom.isEmpty &&
                !advisingActive) {
              return buildRefreshEmptyState(
                onRefresh: _handleRefresh,
                message: 'No class, exam, or personal event found',
              );
            }
            return buildRefreshEmptyState(
              onRefresh: _handleRefresh,
              message: _showDoneAlarms
                  ? 'No completed alarm'
                  : 'No active alarm',
            );
          }

          final highlightedExamKey = _resolveHighlightedExamKey(filteredExams);
          _highlightScroll.clearHighlightKey();

          final highlightedIndex = highlightedExamKey == null
              ? -1
              : filteredExams.indexWhere(
                  (exam) => exam.id == highlightedExamKey,
                );
          unawaited(
            _highlightScroll.scrollToTarget(
              targetToken: highlightedExamKey,
              targetIndex: highlightedIndex >= 0
                  ? (showAdvisingSingle ? 1 : 0) +
                        filteredCustom.length +
                        filteredSections.length +
                        highlightedIndex
                  : null,
              itemCount:
                  (showAdvisingSingle ? 1 : 0) +
                  filteredCustom.length +
                  filteredSections.length +
                  filteredExams.length +
                  1,
              onRetryBuild: () {
                if (mounted) {
                  setState(() {});
                }
              },
            ),
          );

          return BracuRefreshListBuilder(
            onRefresh: _handleRefresh,
            controller: _scrollController,
            itemCount:
                (showAdvisingSingle ? 1 : 0) +
                filteredCustom.length +
                filteredSections.length +
                filteredExams.length +
                1,
            itemBuilder: (context, index) {
              if (showAdvisingSingle && index == 0) {
                final info = advisingInfo!;
                final startDate = DateTime.tryParse(
                  info['advisingStartDate'] ?? '',
                );
                final endDate = DateTime.tryParse(
                  info['advisingEndDate'] ?? '',
                );
                if (startDate != null && endDate != null) {
                  final phase = info['advisingPhase'] ?? '';
                  final semester = info['semesterSession'] ?? '';
                  final phaseLabel = phase.isEmpty
                      ? 'Advising'
                      : phase
                            .split('_')
                            .map(
                              (w) => w.isEmpty
                                  ? ''
                                  : w[0].toUpperCase() +
                                        w.substring(1).toLowerCase(),
                            )
                            .join(' ');
                  final title = semester.isEmpty
                      ? phaseLabel
                      : '$phaseLabel - $semester';
                  final subtitle = formatDateTimeRange(startDate, endDate);
                  final alarmKey =
                      'advising_${startDate.millisecondsSinceEpoch}';
                  _minutesBefore.putIfAbsent(alarmKey, () => 15);

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: BracuCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const SectionBadge(
                                label: 'AD',
                                color: BracuPalette.primary,
                              ),
                              const Gap(12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      title,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const Gap(6),
                                    Text(
                                      subtitle,
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
                            ],
                          ),
                          const Gap(12),
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
                          const Gap(12),
                          (() {
                            final isDone =
                                AppStorage.instance.getBoolSync(
                                  'alarm_done_$alarmKey',
                                ) ==
                                true;
                            return SizedBox(
                              width: double.infinity,
                              child: BracuActionButton(
                                onPressed: () async {
                                  if (isDone) {
                                    final confirmed =
                                        await showBracuConfirmationWithActionDialog(
                                          context,
                                          icon: Icons.delete_outline_rounded,
                                          title: 'Remove Alarm?',
                                          message:
                                              'This will remove the set alarm for $title.',
                                          confirmLabel: 'Remove',
                                          confirmColor: BracuPalette.danger,
                                          onConfirm: () async {
                                            await AppStorage.instance.remove(
                                              'alarm_done_$alarmKey',
                                            );
                                          },
                                        );
                                    if (!confirmed || !context.mounted) return;
                                    showAppSnackBar(context, 'Alarm removed.');
                                    setState(() {});
                                  } else {
                                    await _setAdvisingAlarm(
                                      context,
                                      title,
                                      startDate,
                                      _minutesBefore[alarmKey]!,
                                    );
                                  }
                                },
                                icon: isDone
                                    ? Icons.delete_outline_rounded
                                    : Icons.notifications_active,
                                label: isDone ? 'Remove' : 'Set Alarm',
                              ),
                            );
                          })(),
                        ],
                      ),
                    ),
                  );
                }
              }

              final valIndex = showAdvisingSingle ? index - 1 : index;
              if (valIndex ==
                  filteredCustom.length +
                      filteredSections.length +
                      filteredExams.length) {
                return const Padding(padding: EdgeInsets.only(top: 12));
              }

              if (valIndex < filteredCustom.length) {
                final item = filteredCustom[valIndex];
                final alarmKey = 'custom_${item.itemId}';
                _minutesBefore.putIfAbsent(alarmKey, () => 15);
                final startTime = item.startTime.toLocal();
                final endTime = item.endTime?.toLocal();
                final subtitle = endTime == null
                    ? DateFormat('hh:mm a').format(startTime)
                    : '${DateFormat('hh:mm a').format(startTime)} - ${DateFormat('hh:mm a').format(endTime)}';
                final dateStr = formatDateTimeLabel(item.startTime);

                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: BracuCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            SectionBadge(
                              label: personalSchedulesSectionBadgeLabel(
                                item,
                                courseOptions,
                              ),
                              color: BracuPalette.primary,
                            ),
                            const Gap(12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.title,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const Gap(6),
                                  Text(
                                    subtitle,
                                    style: TextStyle(
                                      color: BracuPalette.textPrimary(context),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const Gap(12),
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
                                  dateStr,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: BracuPalette.textPrimary(context),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (item.notes.trim().isNotEmpty) ...[
                          const Gap(8),
                          Text(
                            item.notes.trim(),
                            style: TextStyle(
                              fontSize: 12,
                              color: BracuPalette.textSecondary(context),
                            ),
                          ),
                        ],
                        const Gap(12),
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
                                      color: BracuPalette.textPrimary(context),
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
                        const Gap(12),
                        (() {
                          final isDone =
                              AppStorage.instance.getBoolSync(
                                'alarm_done_$alarmKey',
                              ) ==
                              true;
                          return SizedBox(
                            width: double.infinity,
                            child: BracuActionButton(
                              onPressed: () async {
                                if (isDone) {
                                  final confirmed =
                                      await showBracuConfirmationWithActionDialog(
                                        context,
                                        icon: Icons.delete_outline_rounded,
                                        title: 'Remove Alarm?',
                                        message:
                                            'This will remove the set alarm for ${item.title}.',
                                        confirmLabel: 'Remove',
                                        confirmColor: BracuPalette.danger,
                                        onConfirm: () async {
                                          await AppStorage.instance.remove(
                                            'alarm_done_$alarmKey',
                                          );
                                        },
                                      );
                                  if (!confirmed || !context.mounted) return;
                                  showAppSnackBar(
                                    context,
                                    'Alarm removed for ${item.title}.',
                                  );
                                  setState(() {});
                                } else {
                                  await _setCustomScheduleAlarm(
                                    context,
                                    item,
                                    _minutesBefore[alarmKey]!,
                                  );
                                }
                              },
                              icon: isDone
                                  ? Icons.delete_outline_rounded
                                  : Icons.notifications_active,
                              label: isDone ? 'Remove' : 'Set Alarm',
                            ),
                          );
                        })(),
                      ],
                    ),
                  ),
                );
              }

              final offsetIndex = valIndex - filteredCustom.length;
              if (offsetIndex >= filteredSections.length &&
                  filteredExams.isNotEmpty) {
                final examIndex = offsetIndex - filteredSections.length;
                final exam = filteredExams[examIndex];
                final alarmKey = 'exam_${exam.id}';
                _minutesBefore.putIfAbsent(alarmKey, () => 15);
                final isHighlighted = highlightedExamKey == exam.id;
                if (isHighlighted) {
                  _highlightScroll.markHighlighted(true);
                }
                return Padding(
                  key: isHighlighted ? _highlightScroll.highlightKey : null,
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      BracuCard(
                        isHighlighted: isHighlighted,
                        highlightColor: BracuPalette.primary,
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
                                const Gap(12),
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
                                      const Gap(6),
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
                                const Gap(8),
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
                                      const Gap(2),
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
                            const Gap(12),
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
                            const Gap(12),
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
                            const Gap(12),
                            (() {
                              final isDone =
                                  AppStorage.instance.getBoolSync(
                                        'alarm_done_$alarmKey',
                                      ) ==
                                      true ||
                                  exam.isPassed;
                              return SizedBox(
                                width: double.infinity,
                                child: BracuActionButton(
                                  onPressed: () async {
                                    if (isDone) {
                                      final confirmed =
                                          await showBracuConfirmationWithActionDialog(
                                            context,
                                            icon: Icons.delete_outline_rounded,
                                            title: 'Remove Alarm?',
                                            message:
                                                'This will remove the set alarm for ${exam.courseCode} ${exam.type}.',
                                            confirmLabel: 'Remove',
                                            confirmColor: BracuPalette.danger,
                                            onConfirm: () async {
                                              await AppStorage.instance.remove(
                                                'alarm_done_$alarmKey',
                                              );
                                            },
                                          );
                                      if (!confirmed || !context.mounted) {
                                        return;
                                      }
                                      showAppSnackBar(
                                        context,
                                        'Alarm removed for ${exam.courseCode} ${exam.type}.',
                                      );
                                      setState(() {});
                                    } else {
                                      await _setExamAlarm(
                                        context,
                                        exam,
                                        _minutesBefore[alarmKey]!,
                                      );
                                    }
                                  },
                                  icon: isDone
                                      ? Icons.delete_outline_rounded
                                      : Icons.notifications_active,
                                  label: isDone ? 'Remove' : 'Set Alarm',
                                ),
                              );
                            })(),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }

              final section = filteredSections[offsetIndex];
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
                      const Gap(12),
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
                      const Gap(12),
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
                      const Gap(12),
                      (() {
                        final isDone =
                            AppStorage.instance.getBoolSync(
                              'alarm_done_$courseCode',
                            ) ==
                            true;
                        return SizedBox(
                          width: double.infinity,
                          child: BracuActionButton(
                            onPressed: () async {
                              if (isDone) {
                                final confirmed =
                                    await showBracuConfirmationWithActionDialog(
                                      context,
                                      icon: Icons.delete_outline_rounded,
                                      title: 'Remove Alarm?',
                                      message:
                                          'This will remove the set alarm for $courseCode.',
                                      confirmLabel: 'Remove',
                                      confirmColor: BracuPalette.danger,
                                      onConfirm: () async {
                                        await AppStorage.instance.remove(
                                          'alarm_done_$courseCode',
                                        );
                                      },
                                    );
                                if (!confirmed || !context.mounted) return;
                                showAppSnackBar(
                                  context,
                                  'Alarm removed for $courseCode.',
                                );
                                setState(() {});
                              } else {
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
                              }
                            },
                            icon: isDone
                                ? Icons.delete_outline_rounded
                                : Icons.notifications_active,
                            label: isDone ? 'Remove' : 'Set Alarm',
                          ),
                        );
                      })(),
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
