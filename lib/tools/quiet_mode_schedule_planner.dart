import 'package:preconnect/api/custom_schedules.dart';
import 'package:preconnect/api/exam_map.dart';
import 'package:preconnect/api/schedule.dart';
import 'package:preconnect/model/custom_schedule.dart';
import 'package:preconnect/model/section_info.dart' as section;
import 'package:preconnect/pages/shared_widgets/current_session_helper.dart';
import 'package:preconnect/tools/ramadan.dart';
import 'package:preconnect/tools/time_utils.dart';

class QuietModeScheduleWindow {
  const QuietModeScheduleWindow({
    required this.startAt,
    required this.endAt,
    required this.source,
    required this.label,
  });

  final DateTime startAt;
  final DateTime endAt;
  final String source;
  final String label;

  bool get isValid => endAt.isAfter(startAt);

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'startAt': startAt.millisecondsSinceEpoch,
      'endAt': endAt.millisecondsSinceEpoch,
      'source': source,
      'label': label,
    };
  }
}

class QuietModeSchedulePlan {
  const QuietModeSchedulePlan({required this.windows, required this.activeNow});

  final List<QuietModeScheduleWindow> windows;
  final bool activeNow;

  bool get isEmpty => windows.isEmpty;

  List<Map<String, dynamic>> toJsonList() {
    return windows.map((window) => window.toJson()).toList(growable: false);
  }
}

class QuietModeSchedulePlanner {
  Future<QuietModeSchedulePlan> buildPlan() async {
    final now = DateTime.now();
    final rawWindows = <QuietModeScheduleWindow>[];

    try {
      final semesterSessionId = await resolveCurrentSessionSemesterId();
      final scheduleService = ScheduleService();
      if (semesterSessionId == null) {
        return const QuietModeSchedulePlan(
          windows: <QuietModeScheduleWindow>[],
          activeNow: false,
        );
      }
      final scheduleJson = await scheduleService.getStudentScheduleForSemester(
        semesterSessionId: semesterSessionId,
      );
      final sections = scheduleService.parseStudentSections(
        scheduleJson,
        semesterSessionId: semesterSessionId,
      );

      if (sections.isNotEmpty) {
        final examService = ExamScheduleService();
        final overrides = await examService.getOverridesForSections(
          sections,
          forcedSemesterSessionId: semesterSessionId,
        );
        final isRamadan = await RamadanTiming.isRamadan();
        rawWindows.addAll(
          _buildClassWindows(sections, isRamadan: isRamadan, now: now),
        );
        rawWindows.addAll(
          _buildExamWindows(sections, overrides: overrides, now: now),
        );
      }
    } catch (_) {}

    try {
      final customItems = await CustomSchedulesService().getCachedItems();
      if (customItems != null && customItems.isNotEmpty) {
        rawWindows.addAll(_buildCustomWindows(customItems, now: now));
      }
    } catch (_) {}

    final merged = _mergeWindows(
      rawWindows.where((window) => window.isValid).toList(),
    );
    final activeNow = merged.any(
      (window) => !now.isBefore(window.startAt) && now.isBefore(window.endAt),
    );
    final futureWindows = merged.where((window) => window.endAt.isAfter(now));

    return QuietModeSchedulePlan(
      windows: futureWindows.toList(growable: false),
      activeNow: activeNow,
    );
  }

  List<QuietModeScheduleWindow> _buildClassWindows(
    List<section.Section> sections, {
    required bool isRamadan,
    required DateTime now,
  }) {
    final windows = <QuietModeScheduleWindow>[];
    for (final sectionItem in sections) {
      final schedule = sectionItem.sectionSchedule;
      final startDate = BracuTime.parseDate(schedule.classStartDate);
      final endDate = BracuTime.parseDate(schedule.classEndDate);
      if (startDate == null || endDate == null) continue;

      final normalizedStart = DateTime(
        startDate.year,
        startDate.month,
        startDate.day,
      );
      final normalizedEnd = DateTime(endDate.year, endDate.month, endDate.day);
      if (normalizedEnd.isBefore(normalizedStart)) continue;

      for (
        var day = normalizedStart;
        !day.isAfter(normalizedEnd);
        day = day.add(const Duration(days: 1))
      ) {
        for (final slot in schedule.classSchedules) {
          final weekday = BracuTime.weekdayFromName(slot.day);
          if (weekday == null || weekday != day.weekday) continue;

          final adjusted = RamadanTiming.adjustRange(
            slot.startTime,
            slot.endTime,
            isRamadan: isRamadan,
          );
          final startHm = BracuTime.parseHourMinute(adjusted.startTime);
          final endHm = BracuTime.parseHourMinute(adjusted.endTime);
          if (startHm == null || endHm == null) continue;

          final startAt = DateTime(
            day.year,
            day.month,
            day.day,
            startHm.$1,
            startHm.$2,
          );
          final endAt = DateTime(
            day.year,
            day.month,
            day.day,
            endHm.$1,
            endHm.$2,
          );
          if (!endAt.isAfter(startAt)) continue;
          if (endAt.isBefore(now)) continue;

          windows.add(
            QuietModeScheduleWindow(
              startAt: startAt,
              endAt: endAt,
              source: 'class',
              label:
                  '${sectionItem.courseCode.trim().toUpperCase()} ${sectionItem.sectionName.trim()}'
                      .trim(),
            ),
          );
        }
      }
    }
    return windows;
  }

  List<QuietModeScheduleWindow> _buildExamWindows(
    List<section.Section> sections, {
    required Map<String, ExamScheduleOverride> overrides,
    required DateTime now,
  }) {
    final windows = <QuietModeScheduleWindow>[];
    final examService = ExamScheduleService();

    for (final sectionItem in sections) {
      final resolved = examService.resolveSection(
        section: sectionItem,
        overrides: overrides,
      );

      void addWindow({
        required String? date,
        required String? startTime,
        required String? endTime,
        required String label,
        required String source,
      }) {
        final start = BracuTime.parseDateTime(date, startTime);
        final end = BracuTime.parseDateTime(date, endTime);
        if (start == null || end == null) return;
        if (!end.isAfter(start)) return;
        if (end.isBefore(now)) return;
        windows.add(
          QuietModeScheduleWindow(
            startAt: start,
            endAt: end,
            source: source,
            label: label,
          ),
        );
      }

      final courseCode = sectionItem.courseCode.trim().toUpperCase();
      addWindow(
        date: resolved.midDate,
        startTime: resolved.midStartTime,
        endTime: resolved.midEndTime,
        source: 'exam_mid',
        label: '$courseCode Midterm',
      );
      addWindow(
        date: resolved.finalDate,
        startTime: resolved.finalStartTime,
        endTime: resolved.finalEndTime,
        source: 'exam_final',
        label: '$courseCode Final',
      );
    }

    return windows;
  }

  List<QuietModeScheduleWindow> _buildCustomWindows(
    List<CustomSchedule> items, {
    required DateTime now,
  }) {
    return items
        .where((item) {
          return !item.isDone && item.endTime != null;
        })
        .map((item) {
          final endTime = item.endTime!;
          return QuietModeScheduleWindow(
            startAt: item.startTime,
            endAt: endTime,
            source: 'custom',
            label: item.title.trim().isEmpty ? item.kind : item.title.trim(),
          );
        })
        .where((window) {
          return window.isValid && window.endAt.isAfter(now);
        })
        .toList(growable: false);
  }

  List<QuietModeScheduleWindow> _mergeWindows(
    List<QuietModeScheduleWindow> windows,
  ) {
    if (windows.isEmpty) return const <QuietModeScheduleWindow>[];
    final sorted = List<QuietModeScheduleWindow>.from(windows)
      ..sort((a, b) => a.startAt.compareTo(b.startAt));

    final merged = <QuietModeScheduleWindow>[sorted.first];
    for (final window in sorted.skip(1)) {
      final last = merged.last;
      if (window.startAt.isAfter(last.endAt)) {
        merged.add(window);
        continue;
      }

      final mergedEnd = window.endAt.isAfter(last.endAt)
          ? window.endAt
          : last.endAt;
      merged[merged.length - 1] = QuietModeScheduleWindow(
        startAt: last.startAt,
        endAt: mergedEnd,
        source: last.source,
        label: last.label,
      );
    }

    return merged;
  }
}
