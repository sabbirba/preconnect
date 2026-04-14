import 'package:intl/intl.dart';
import 'package:preconnect/model/schedule_planner_item.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/ramadan_timing.dart';
import 'package:preconnect/tools/time_utils.dart';

typedef SchedulePlannerDraft = ({
  String kind,
  String title,
  String courseCode,
  String sectionName,
  DateTime startTime,
  DateTime? endTime,
  bool useReminder,
  DateTime? reminderAt,
  String notes,
  bool isDone,
});

typedef SchedulePlannerSetAlarmCallback =
    Future<void> Function({
      required String courseCode,
      required String title,
      required DateTime reminderAt,
    });

typedef SchedulePlannerDeleteCallback = Future<void> Function();
typedef SchedulePlannerToggleDoneCallback = Future<void> Function(bool isDone);

typedef SchedulePlannerClassSchedule = ({
  String day,
  String startTime,
  String endTime,
});

typedef SchedulePlannerCourseOption = ({
  String courseCode,
  String sectionName,
  List<SchedulePlannerClassSchedule> classSchedules,
});

typedef SchedulePlannerTitleTemplate = ({
  SchedulePlannerCourseOption courseOption,
  String sectionName,
  String kind,
});

List<SchedulePlannerCourseOption> schedulePlannerCourseOptionsForDropdown({
  required List<SchedulePlannerCourseOption> courseOptions,
  required SchedulePlannerItem? item,
}) {
  final normalized = <SchedulePlannerCourseOption>[];
  final seen = <String>{};
  for (final option in courseOptions) {
    final code = option.courseCode.trim().toUpperCase();
    if (code.isEmpty) continue;
    final next = (
      courseCode: code,
      sectionName: option.sectionName.trim(),
      classSchedules: option.classSchedules,
    );
    if (seen.add(schedulePlannerCourseOptionIdentity(next))) {
      normalized.add(next);
    }
  }
  final currentCourseCode = item?.courseCode.trim().toUpperCase();
  if (currentCourseCode != null && currentCourseCode.isNotEmpty) {
    final current = (
      courseCode: currentCourseCode,
      sectionName: '',
      classSchedules: const <SchedulePlannerClassSchedule>[],
    );
    if (seen.add(schedulePlannerCourseOptionIdentity(current))) {
      normalized.add(current);
    }
  }
  normalized.sort((a, b) {
    final codeCmp = a.courseCode.compareTo(b.courseCode);
    if (codeCmp != 0) return codeCmp;
    return a.sectionName.compareTo(b.sectionName);
  });
  return normalized;
}

String schedulePlannerCourseOptionIdentity(SchedulePlannerCourseOption option) {
  return '${option.courseCode}|${option.sectionName}';
}

const String _plannerTitleSeparator = '  ';

List<String> _splitSchedulePlannerTitleParts(String title) {
  return title
      .split(RegExp(r'\s*•\s*|\s{2,}'))
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .toList();
}

String _joinSchedulePlannerTitleParts(Iterable<String> parts) {
  return parts
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .join(_plannerTitleSeparator);
}

SchedulePlannerCourseOption? schedulePlannerSelectDefaultCourseOption(
  List<SchedulePlannerCourseOption> options, {
  required bool isRamadan,
}) {
  if (options.isEmpty) return null;

  final usableOptions = options.where(
    (option) => schedulePlannerHasUsableSectionLabel(option.sectionName),
  );
  final pool = usableOptions.isNotEmpty ? usableOptions.toList() : options;

  final now = DateTime.now();
  SchedulePlannerCourseOption? bestOption;
  DateTime? bestOccurrence;

  for (final option in pool) {
    final occurrence = schedulePlannerBestOccurrenceForOption(
      option,
      now: now,
      isRamadan: isRamadan,
    );
    if (occurrence == null) continue;
    if (bestOccurrence == null || occurrence.isBefore(bestOccurrence)) {
      bestOccurrence = occurrence;
      bestOption = option;
    }
  }

  return bestOption ?? pool.first;
}

DateTime? schedulePlannerBestOccurrenceForOption(
  SchedulePlannerCourseOption option, {
  required DateTime now,
  required bool isRamadan,
}) {
  DateTime? best;
  final nowMinutes = now.hour * 60 + now.minute;
  for (final schedule in option.classSchedules) {
    final occurrence = schedulePlannerNextOccurrence(
      day: schedule.day,
      startTime: schedule.startTime,
      endTime: schedule.endTime,
      isRamadan: isRamadan,
      now: now,
      nowMinutes: nowMinutes,
    );
    if (occurrence == null) continue;
    if (best == null || occurrence.isBefore(best)) {
      best = occurrence;
    }
  }
  return best;
}

DateTime? schedulePlannerNextOccurrence({
  required String day,
  required String startTime,
  required String endTime,
  required bool isRamadan,
  required DateTime now,
  required int nowMinutes,
}) {
  final targetWeekday = BracuTime.weekdayFromName(day);
  if (targetWeekday == null) return null;

  final adjusted = RamadanTiming.adjustRange(
    startTime,
    endTime,
    isRamadan: isRamadan,
  );

  final startParsed = BracuTime.parseHourMinute(adjusted.startTime);
  if (startParsed == null) return null;
  final (startHour, startMinute) = startParsed;
  final startMinutes = startHour * 60 + startMinute;

  final endParsed = BracuTime.parseHourMinute(adjusted.endTime);
  final endHour = endParsed?.$1 ?? 0;
  final endMinute = endParsed?.$2 ?? 0;
  final endMinutes = endHour * 60 + endMinute;

  final dayDelta = (targetWeekday - now.weekday + 7) % 7;
  if (dayDelta == 0) {
    if (nowMinutes >= endMinutes) {
      return null;
    }
    if (nowMinutes <= startMinutes) {
      return DateTime(now.year, now.month, now.day, startHour, startMinute);
    }
    return now;
  }

  final nextDate = now.add(Duration(days: dayDelta));
  return DateTime(
    nextDate.year,
    nextDate.month,
    nextDate.day,
    startHour,
    startMinute,
  );
}

bool schedulePlannerHasUsableSectionLabel(String value) {
  return formatSectionBadge(value) != '?';
}

int schedulePlannerSectionRank(String value) {
  final badge = formatSectionBadge(value);
  if (badge == '?') return 9999;
  return int.tryParse(badge) ?? 9999;
}

SchedulePlannerCourseOption? schedulePlannerFindCourseOption(
  List<SchedulePlannerCourseOption> options,
  String courseCode, {
  String? preferredSectionName,
}) {
  final normalizedCode = courseCode.trim().toUpperCase();
  final normalizedSection = preferredSectionName?.trim() ?? '';
  if (normalizedCode.isEmpty) {
    return options.isNotEmpty ? options.first : null;
  }

  if (normalizedSection.isNotEmpty) {
    for (final option in options) {
      if (option.courseCode == normalizedCode &&
          option.sectionName.trim() == normalizedSection) {
        return option;
      }
    }
  }

  final preferredMatches = options
      .where(
        (option) =>
            option.courseCode == normalizedCode &&
            schedulePlannerHasUsableSectionLabel(option.sectionName),
      )
      .toList();
  if (preferredMatches.isNotEmpty) {
    preferredMatches.sort((a, b) {
      final sectionCmp = schedulePlannerSectionRank(
        a.sectionName,
      ).compareTo(schedulePlannerSectionRank(b.sectionName));
      if (sectionCmp != 0) return sectionCmp;
      return a.sectionName.compareTo(b.sectionName);
    });
    return preferredMatches.first;
  }

  for (final option in options) {
    if (option.courseCode == normalizedCode) {
      return option;
    }
  }
  return options.isNotEmpty ? options.first : null;
}

String schedulePlannerTitleSectionCandidate(String title) {
  final parts = _splitSchedulePlannerTitleParts(title);
  if (parts.length < 2) return '';
  return parts[1];
}

String schedulePlannerResolveSectionName({
  required String courseCode,
  required String sectionName,
  required String title,
  required List<SchedulePlannerCourseOption> courseOptions,
}) {
  final direct = sectionName.trim();
  if (schedulePlannerHasUsableSectionLabel(direct)) return direct;

  final titleSection = schedulePlannerTitleSectionCandidate(title);
  if (schedulePlannerHasUsableSectionLabel(titleSection)) {
    return titleSection.trim();
  }

  final normalizedCode = courseCode.trim().toUpperCase();
  if (normalizedCode.isEmpty) return direct;

  final sameCodeMatches = courseOptions
      .where(
        (option) =>
            option.courseCode == normalizedCode &&
            schedulePlannerHasUsableSectionLabel(option.sectionName),
      )
      .toList();
  if (sameCodeMatches.isNotEmpty) {
    sameCodeMatches.sort((a, b) {
      final sectionCmp = schedulePlannerSectionRank(
        a.sectionName,
      ).compareTo(schedulePlannerSectionRank(b.sectionName));
      if (sectionCmp != 0) return sectionCmp;
      return a.sectionName.compareTo(b.sectionName);
    });
    return sameCodeMatches.first.sectionName.trim();
  }

  if (normalizedCode.endsWith('L') && normalizedCode.length > 1) {
    final baseCode = normalizedCode.substring(0, normalizedCode.length - 1);
    final baseMatches = courseOptions
        .where(
          (option) =>
              option.courseCode == baseCode &&
              schedulePlannerHasUsableSectionLabel(option.sectionName),
        )
        .toList();
    if (baseMatches.isNotEmpty) {
      baseMatches.sort((a, b) {
        final sectionCmp = schedulePlannerSectionRank(
          a.sectionName,
        ).compareTo(schedulePlannerSectionRank(b.sectionName));
        if (sectionCmp != 0) return sectionCmp;
        return a.sectionName.compareTo(b.sectionName);
      });
      return baseMatches.first.sectionName.trim();
    }
  }

  return direct;
}

List<SchedulePlannerTitleTemplate> schedulePlannerTitleTemplates({
  required List<SchedulePlannerCourseOption> courseOptions,
  required SchedulePlannerItem? item,
}) {
  final templates = <SchedulePlannerTitleTemplate>[];
  final kinds = const ['quiz', 'assignment', 'reminder'];
  for (final course in schedulePlannerCourseOptionsForDropdown(
    courseOptions: courseOptions,
    item: item,
  )) {
    final resolvedSectionName = schedulePlannerResolveSectionName(
      courseCode: course.courseCode,
      sectionName: course.sectionName,
      title: item?.title.trim() ?? '',
      courseOptions: courseOptions,
    );
    for (final nextKind in kinds) {
      templates.add((
        courseOption: course,
        sectionName: resolvedSectionName,
        kind: nextKind,
      ));
    }
  }
  return templates;
}

SchedulePlannerTitleTemplate? schedulePlannerCurrentTemplateBySelection({
  required List<SchedulePlannerCourseOption> courseOptions,
  required SchedulePlannerItem? item,
  required SchedulePlannerCourseOption? selectedCourseOption,
  required String resolvedSectionName,
  required String kind,
}) {
  final courseOption =
      selectedCourseOption ??
      schedulePlannerFindCourseOption(
        schedulePlannerCourseOptionsForDropdown(
          courseOptions: courseOptions,
          item: item,
        ),
        item?.courseCode.trim().toUpperCase() ?? '',
      );
  if (courseOption == null) return null;
  return (
    courseOption: courseOption,
    sectionName: schedulePlannerResolveSectionName(
      courseCode: courseOption.courseCode,
      sectionName: resolvedSectionName.isNotEmpty
          ? resolvedSectionName
          : courseOption.sectionName,
      title: item?.title.trim() ?? '',
      courseOptions: courseOptions,
    ),
    kind: kind,
  );
}

String schedulePlannerTitleTemplateLabel(
  SchedulePlannerTitleTemplate template,
) {
  final courseCode = template.courseOption.courseCode.trim().toUpperCase();
  return '$courseCode$_plannerTitleSeparator${schedulePlannerKindLabel(template.kind)}';
}

String schedulePlannerGeneratedTitle({
  required String kind,
  required SchedulePlannerCourseOption? selectedCourseOption,
  required List<SchedulePlannerCourseOption> courseOptions,
  required SchedulePlannerItem? item,
  String? courseCode,
}) {
  final code =
      (courseCode ?? selectedCourseOption?.courseCode ?? item?.courseCode ?? '')
          .trim()
          .toUpperCase();
  final kindLabel = schedulePlannerKindLabel(kind);
  if (code.isEmpty) return kindLabel;
  return '$code$_plannerTitleSeparator$kindLabel';
}

String schedulePlannerNormalizeTitle(String title) {
  final parts = _splitSchedulePlannerTitleParts(title);
  if (parts.length >= 3) {
    return _joinSchedulePlannerTitleParts(<String>[
      parts[0],
      parts[1],
      parts.sublist(2).join(_plannerTitleSeparator),
    ]);
  }
  if (parts.length < 2) return title;
  final kind = parts.last.toLowerCase();
  if (kind != 'quiz' && kind != 'assignment' && kind != 'reminder') {
    return title;
  }
  final code = parts.first;
  return '$code$_plannerTitleSeparator${schedulePlannerKindLabel(kind)}';
}

String schedulePlannerComposeTitle({
  required String courseCode,
  required String sectionName,
  required String suffix,
}) {
  final code = courseCode.trim().toUpperCase();
  final section = sectionName.trim();
  final extra = suffix.trim();
  if (code.isEmpty) return extra;
  if (section.isEmpty) {
    return extra.isEmpty ? code : '$code$_plannerTitleSeparator$extra';
  }
  if (extra.isEmpty) return '$code$_plannerTitleSeparator$section';
  return '$code$_plannerTitleSeparator$section$_plannerTitleSeparator$extra';
}

String schedulePlannerInitialSuffix(
  String rawTitle, {
  required String courseCode,
  required String sectionName,
}) {
  final parts = _splitSchedulePlannerTitleParts(rawTitle);
  if (parts.isEmpty) return '';
  final normalizedCode = courseCode.trim().toUpperCase();
  final normalizedSection = sectionName.trim();
  if (parts.length >= 3 &&
      parts.first.toUpperCase() == normalizedCode &&
      (parts[1] == normalizedSection ||
          (!schedulePlannerHasUsableSectionLabel(parts[1]) &&
              normalizedSection.isNotEmpty))) {
    return _joinSchedulePlannerTitleParts(parts.sublist(2));
  }
  if (parts.length >= 2 && parts.first.toUpperCase() == normalizedCode) {
    return _joinSchedulePlannerTitleParts(parts.sublist(1));
  }
  return rawTitle.trim();
}

String schedulePlannerKindLabel(String kind) {
  switch (kind) {
    case 'quiz':
      return 'Quiz';
    case 'assignment':
      return 'Assignment';
    case 'reminder':
      return 'Reminder';
    default:
      final value = kind.trim();
      if (value.isEmpty) return 'Task';
      return value[0].toUpperCase() + value.substring(1).toLowerCase();
  }
}

String schedulePlannerFormatKind(String kind) {
  return schedulePlannerKindLabel(kind);
}

String schedulePlannerFormatDueDate(DateTime dueAt) {
  return DateFormat('dd MMM, hh:mm a').format(dueAt);
}

String schedulePlannerCardTitle(String rawTitle) {
  final parts = _splitSchedulePlannerTitleParts(rawTitle);
  if (parts.length >= 3) {
    return _joinSchedulePlannerTitleParts(<String>[
      parts[0],
      parts.sublist(2).join(_plannerTitleSeparator),
    ]);
  }
  if (parts.length < 2) return rawTitle.trim();
  final kind = parts.last.toLowerCase();
  if (kind != 'quiz' && kind != 'assignment' && kind != 'reminder') {
    return rawTitle.trim();
  }
  return '${parts.first}$_plannerTitleSeparator${parts.last}';
}

String schedulePlannerNormalizeTitleForSave(String rawTitle) {
  final parts = _splitSchedulePlannerTitleParts(rawTitle);
  if (parts.length >= 3) {
    return _joinSchedulePlannerTitleParts(<String>[
      parts[0],
      parts[1],
      parts.sublist(2).join(_plannerTitleSeparator),
    ]);
  }
  if (parts.length < 2) return rawTitle.trim();
  final kind = parts.last.toLowerCase();
  if (kind != 'quiz' && kind != 'assignment' && kind != 'reminder') {
    return rawTitle.trim();
  }
  return '${parts.first}$_plannerTitleSeparator${parts.last}';
}

String schedulePlannerSectionBadgeLabel(
  SchedulePlannerItem item,
  List<SchedulePlannerCourseOption> courseOptions,
) {
  final direct = formatSectionBadge(item.sectionName);
  if (direct != '?') return direct;
  final parts = _splitSchedulePlannerTitleParts(item.title);
  if (parts.length >= 2) {
    final fallback = formatSectionBadge(parts[1]);
    if (fallback != '?') return fallback;
  }
  final inferred = schedulePlannerResolveSectionName(
    courseCode: item.courseCode,
    sectionName: item.sectionName,
    title: item.title,
    courseOptions: courseOptions,
  );
  final inferredBadge = formatSectionBadge(inferred);
  if (inferredBadge != '?') return inferredBadge;
  return direct;
}
