import 'package:intl/intl.dart';
import 'package:preconnect/model/personal_schedule.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/ramadan_timing.dart';
import 'package:preconnect/tools/time_utils.dart';

typedef PersonalSchedulesDraft = ({
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

typedef PersonalSchedulesSetAlarmCallback =
    Future<void> Function({
      required String courseCode,
      required String title,
      required DateTime reminderAt,
    });

typedef PersonalSchedulesDeleteCallback = Future<void> Function();
typedef PersonalSchedulesToggleDoneCallback =
    Future<void> Function(bool isDone);

typedef PersonalSchedulesClassSchedule = ({
  String day,
  String startTime,
  String endTime,
});

typedef PersonalSchedulesOccurrence = ({DateTime startTime, DateTime endTime});

typedef PersonalSchedulesCourseOption = ({
  String courseCode,
  String sectionName,
  List<PersonalSchedulesClassSchedule> classSchedules,
});

typedef PersonalSchedulesTitleTemplate = ({
  PersonalSchedulesCourseOption courseOption,
  String sectionName,
  String kind,
});

List<PersonalSchedulesCourseOption> personalSchedulesCourseOptionsForDropdown({
  required List<PersonalSchedulesCourseOption> courseOptions,
  required PersonalSchedule? item,
}) {
  final normalized = <PersonalSchedulesCourseOption>[];
  final seen = <String>{};
  for (final option in courseOptions) {
    final code = option.courseCode.trim().toUpperCase();
    if (code.isEmpty) continue;
    final next = (
      courseCode: code,
      sectionName: option.sectionName.trim(),
      classSchedules: option.classSchedules,
    );
    if (seen.add(personalSchedulesCourseOptionIdentity(next))) {
      normalized.add(next);
    }
  }
  final currentCourseCode = item?.courseCode.trim().toUpperCase();
  if (currentCourseCode != null && currentCourseCode.isNotEmpty) {
    final current = (
      courseCode: currentCourseCode,
      sectionName: '',
      classSchedules: const <PersonalSchedulesClassSchedule>[],
    );
    if (seen.add(personalSchedulesCourseOptionIdentity(current))) {
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

String personalSchedulesCourseOptionIdentity(
  PersonalSchedulesCourseOption option,
) {
  return '${option.courseCode}|${option.sectionName}';
}

const String _myTitleSeparator = ' ';

List<String> _splitPersonalSchedulesTitleParts(String title) {
  return title
      .split(RegExp(r'\s*•\s*|\s+'))
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .toList();
}

String _joinPersonalSchedulesTitleParts(Iterable<String> parts) {
  return parts
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .join(_myTitleSeparator);
}

PersonalSchedulesCourseOption? personalSchedulesSelectDefaultCourseOption(
  List<PersonalSchedulesCourseOption> options, {
  required bool isRamadan,
}) {
  if (options.isEmpty) return null;

  final usableOptions = options.where(
    (option) => personalSchedulesHasUsableSectionLabel(option.sectionName),
  );
  final pool = usableOptions.isNotEmpty ? usableOptions.toList() : options;

  final now = DateTime.now();
  PersonalSchedulesCourseOption? bestOption;
  DateTime? bestOccurrence;

  for (final option in pool) {
    final occurrence = personalSchedulesBestOccurrenceForOption(
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

DateTime? personalSchedulesBestOccurrenceForOption(
  PersonalSchedulesCourseOption option, {
  required DateTime now,
  required bool isRamadan,
}) {
  DateTime? best;
  final nowMinutes = now.hour * 60 + now.minute;
  for (final schedule in option.classSchedules) {
    final occurrence = personalSchedulesNextOccurrence(
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

PersonalSchedulesOccurrence? personalSchedulesNextOccurrenceRange({
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

  final dayDelta = (targetWeekday - now.weekday + 7) % 7;
  final nextDate = dayDelta == 0 && nowMinutes <= startMinutes
      ? now
      : dayDelta == 0
      ? now
      : now.add(Duration(days: dayDelta));

  if (dayDelta == 0 && nowMinutes >= endHour * 60 + endMinute) {
    return null;
  }

  return (
    startTime: DateTime(
      nextDate.year,
      nextDate.month,
      nextDate.day,
      startHour,
      startMinute,
    ),
    endTime: DateTime(
      nextDate.year,
      nextDate.month,
      nextDate.day,
      endHour,
      endMinute,
    ),
  );
}

PersonalSchedulesOccurrence? personalSchedulesDefaultOccurrenceForOption(
  PersonalSchedulesCourseOption option, {
  required bool isRamadan,
  DateTime? now,
}) {
  final currentTime = now ?? DateTime.now();
  final nowMinutes = currentTime.hour * 60 + currentTime.minute;
  PersonalSchedulesOccurrence? best;
  for (final schedule in option.classSchedules) {
    final occurrence = personalSchedulesNextOccurrenceRange(
      day: schedule.day,
      startTime: schedule.startTime,
      endTime: schedule.endTime,
      isRamadan: isRamadan,
      now: currentTime,
      nowMinutes: nowMinutes,
    );
    if (occurrence == null) continue;
    if (best == null || occurrence.startTime.isBefore(best.startTime)) {
      best = occurrence;
    }
  }
  return best;
}

DateTime? personalSchedulesNextOccurrence({
  required String day,
  required String startTime,
  required String endTime,
  required bool isRamadan,
  required DateTime now,
  required int nowMinutes,
}) {
  final range = personalSchedulesNextOccurrenceRange(
    day: day,
    startTime: startTime,
    endTime: endTime,
    isRamadan: isRamadan,
    now: now,
    nowMinutes: nowMinutes,
  );
  return range?.startTime;
}

bool personalSchedulesHasUsableSectionLabel(String value) {
  return formatSectionBadge(value) != '?';
}

int personalSchedulesSectionRank(String value) {
  final badge = formatSectionBadge(value);
  if (badge == '?') return 9999;
  return int.tryParse(badge) ?? 9999;
}

PersonalSchedulesCourseOption? personalSchedulesFindCourseOption(
  List<PersonalSchedulesCourseOption> options,
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
            personalSchedulesHasUsableSectionLabel(option.sectionName),
      )
      .toList();
  if (preferredMatches.isNotEmpty) {
    preferredMatches.sort((a, b) {
      final sectionCmp = personalSchedulesSectionRank(
        a.sectionName,
      ).compareTo(personalSchedulesSectionRank(b.sectionName));
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

String personalSchedulesTitleSectionCandidate(String title) {
  final parts = _splitPersonalSchedulesTitleParts(title);
  if (parts.length < 2) return '';
  return parts[1];
}

String personalSchedulesResolveSectionName({
  required String courseCode,
  required String sectionName,
  required String title,
  required List<PersonalSchedulesCourseOption> courseOptions,
}) {
  final direct = sectionName.trim();
  if (personalSchedulesHasUsableSectionLabel(direct)) return direct;

  final titleSection = personalSchedulesTitleSectionCandidate(title);
  if (personalSchedulesHasUsableSectionLabel(titleSection)) {
    return titleSection.trim();
  }

  final normalizedCode = courseCode.trim().toUpperCase();
  if (normalizedCode.isEmpty) return direct;

  final sameCodeMatches = courseOptions
      .where(
        (option) =>
            option.courseCode == normalizedCode &&
            personalSchedulesHasUsableSectionLabel(option.sectionName),
      )
      .toList();
  if (sameCodeMatches.isNotEmpty) {
    sameCodeMatches.sort((a, b) {
      final sectionCmp = personalSchedulesSectionRank(
        a.sectionName,
      ).compareTo(personalSchedulesSectionRank(b.sectionName));
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
              personalSchedulesHasUsableSectionLabel(option.sectionName),
        )
        .toList();
    if (baseMatches.isNotEmpty) {
      baseMatches.sort((a, b) {
        final sectionCmp = personalSchedulesSectionRank(
          a.sectionName,
        ).compareTo(personalSchedulesSectionRank(b.sectionName));
        if (sectionCmp != 0) return sectionCmp;
        return a.sectionName.compareTo(b.sectionName);
      });
      return baseMatches.first.sectionName.trim();
    }
  }

  return direct;
}

List<PersonalSchedulesTitleTemplate> personalSchedulesTitleTemplates({
  required List<PersonalSchedulesCourseOption> courseOptions,
  required PersonalSchedule? item,
}) {
  final templates = <PersonalSchedulesTitleTemplate>[];
  final kinds = const ['quiz', 'assignment', 'reminder'];
  for (final course in personalSchedulesCourseOptionsForDropdown(
    courseOptions: courseOptions,
    item: item,
  )) {
    final resolvedSectionName = personalSchedulesResolveSectionName(
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

PersonalSchedulesTitleTemplate? personalSchedulesCurrentTemplateBySelection({
  required List<PersonalSchedulesCourseOption> courseOptions,
  required PersonalSchedule? item,
  required PersonalSchedulesCourseOption? selectedCourseOption,
  required String resolvedSectionName,
  required String kind,
}) {
  final courseOption =
      selectedCourseOption ??
      personalSchedulesFindCourseOption(
        personalSchedulesCourseOptionsForDropdown(
          courseOptions: courseOptions,
          item: item,
        ),
        item?.courseCode.trim().toUpperCase() ?? '',
      );
  if (courseOption == null) return null;
  return (
    courseOption: courseOption,
    sectionName: personalSchedulesResolveSectionName(
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

String personalSchedulesTitleTemplateLabel(
  PersonalSchedulesTitleTemplate template,
) {
  final courseCode = template.courseOption.courseCode.trim().toUpperCase();
  return '$courseCode$_myTitleSeparator${personalSchedulesKindLabel(template.kind)}';
}

String personalSchedulesGeneratedTitle({
  required String kind,
  required PersonalSchedulesCourseOption? selectedCourseOption,
  required List<PersonalSchedulesCourseOption> courseOptions,
  required PersonalSchedule? item,
  String? courseCode,
}) {
  final code =
      (courseCode ?? selectedCourseOption?.courseCode ?? item?.courseCode ?? '')
          .trim()
          .toUpperCase();
  final kindLabel = personalSchedulesKindLabel(kind);
  if (code.isEmpty) return kindLabel;
  return '$code$_myTitleSeparator$kindLabel';
}

String personalSchedulesNormalizeTitle(String title) {
  final parts = _splitPersonalSchedulesTitleParts(title);
  if (parts.length >= 3) {
    return _joinPersonalSchedulesTitleParts(<String>[
      parts[0],
      parts[1],
      parts.sublist(2).join(_myTitleSeparator),
    ]);
  }
  if (parts.length < 2) return title;
  final kind = parts.last.toLowerCase();
  if (kind != 'quiz' && kind != 'assignment' && kind != 'reminder') {
    return title;
  }
  final code = parts.first;
  return '$code$_myTitleSeparator${personalSchedulesKindLabel(kind)}';
}

String personalSchedulesComposeTitle({
  required String courseCode,
  required String sectionName,
  required String suffix,
}) {
  final code = courseCode.trim().toUpperCase();
  final section = sectionName.trim();
  final extra = suffix.trim();
  if (code.isEmpty) return extra;
  if (section.isEmpty) {
    return extra.isEmpty ? code : '$code$_myTitleSeparator$extra';
  }
  if (extra.isEmpty) return '$code$_myTitleSeparator$section';
  return '$code$_myTitleSeparator$section$_myTitleSeparator$extra';
}

String personalSchedulesInitialSuffix(
  String rawTitle, {
  required String courseCode,
  required String sectionName,
}) {
  final parts = _splitPersonalSchedulesTitleParts(rawTitle);
  if (parts.isEmpty) return '';
  final normalizedCode = courseCode.trim().toUpperCase();
  final normalizedSection = sectionName.trim();
  if (parts.length >= 3 &&
      parts.first.toUpperCase() == normalizedCode &&
      (parts[1] == normalizedSection ||
          (!personalSchedulesHasUsableSectionLabel(parts[1]) &&
              normalizedSection.isNotEmpty))) {
    return _joinPersonalSchedulesTitleParts(parts.sublist(2));
  }
  if (parts.length >= 2 && parts.first.toUpperCase() == normalizedCode) {
    return _joinPersonalSchedulesTitleParts(parts.sublist(1));
  }
  return rawTitle.trim();
}

String personalSchedulesKindLabel(String kind) {
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

String personalSchedulesFormatKind(String kind) {
  return personalSchedulesKindLabel(kind);
}

String personalSchedulesFormatDueDate(DateTime dueAt) {
  return DateFormat('dd MMM, hh:mm a').format(dueAt);
}

String personalSchedulesCardTitle(String rawTitle) {
  final parts = _splitPersonalSchedulesTitleParts(rawTitle);
  if (parts.length >= 3) {
    return _joinPersonalSchedulesTitleParts(<String>[
      parts[0],
      parts.sublist(2).join(_myTitleSeparator),
    ]);
  }
  if (parts.length < 2) return rawTitle.trim();
  final kind = parts.last.toLowerCase();
  if (kind != 'quiz' && kind != 'assignment' && kind != 'reminder') {
    return rawTitle.trim();
  }
  return '${parts.first}$_myTitleSeparator${parts.last}';
}

String personalSchedulesNormalizeTitleForSave(String rawTitle) {
  final parts = _splitPersonalSchedulesTitleParts(rawTitle);
  if (parts.length >= 3) {
    return _joinPersonalSchedulesTitleParts(<String>[
      parts[0],
      parts[1],
      parts.sublist(2).join(_myTitleSeparator),
    ]);
  }
  if (parts.length < 2) return rawTitle.trim();
  final kind = parts.last.toLowerCase();
  if (kind != 'quiz' && kind != 'assignment' && kind != 'reminder') {
    return rawTitle.trim();
  }
  return '${parts.first}$_myTitleSeparator${parts.last}';
}

String personalSchedulesSectionBadgeLabel(
  PersonalSchedule item,
  List<PersonalSchedulesCourseOption> courseOptions,
) {
  final direct = formatSectionBadge(item.sectionName);
  if (direct != '?') return direct;
  final parts = _splitPersonalSchedulesTitleParts(item.title);
  if (parts.length >= 2) {
    final fallback = formatSectionBadge(parts[1]);
    if (fallback != '?') return fallback;
  }
  final inferred = personalSchedulesResolveSectionName(
    courseCode: item.courseCode,
    sectionName: item.sectionName,
    title: item.title,
    courseOptions: courseOptions,
  );
  final inferredBadge = formatSectionBadge(inferred);
  if (inferredBadge != '?') return inferredBadge;
  return direct;
}
