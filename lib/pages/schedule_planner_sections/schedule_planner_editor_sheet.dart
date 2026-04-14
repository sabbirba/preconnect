// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:preconnect/model/schedule_planner_item.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/ramadan_timing.dart';
import 'package:preconnect/tools/time_utils.dart';

typedef SchedulePlannerDraft = ({
  String kind,
  String title,
  String courseCode,
  DateTime dueAt,
  bool useReminder,
  DateTime? reminderAt,
  String notes,
  bool isDone,
});

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

typedef _TitleTemplate = ({
  SchedulePlannerCourseOption courseOption,
  String kind,
});

Future<SchedulePlannerDraft?> showSchedulePlannerEditorSheet(
  BuildContext context, {
  required SchedulePlannerItem? item,
  required List<SchedulePlannerCourseOption> courseOptions,
}) async {
  final isRamadan = await RamadanTiming.isRamadan();
  final titleController = TextEditingController(
    text: item?.title.trim().isNotEmpty == true ? item!.title.trim() : '',
  );
  final courseCodeController = TextEditingController(
    text: item?.courseCode ?? '',
  );
  final notesController = TextEditingController(text: item?.notes ?? '');
  var kind = item != null && item.kind.isNotEmpty ? item.kind : 'quiz';
  var dueAt = item?.dueAt ?? DateTime.now().add(const Duration(days: 1));
  var useReminder = item?.reminderAt != null;
  var reminderMinutesBefore = item?.reminderAt == null
      ? 60
      : dueAt.difference(item!.reminderAt!).inMinutes;
  if (reminderMinutesBefore < 5) {
    reminderMinutesBefore = 5;
  }
  var isDone = item?.isDone ?? false;

  final availableCourseOptions = _courseOptionsForDropdown(
    courseOptions: courseOptions,
    item: item,
  );
  final initialCourseCode = item?.courseCode.trim().toUpperCase();
  SchedulePlannerCourseOption? selectedCourseOption =
      initialCourseCode != null && initialCourseCode.isNotEmpty
      ? _findCourseOption(availableCourseOptions, initialCourseCode)
      : null;
  selectedCourseOption ??= _selectDefaultCourseOption(
    availableCourseOptions,
    isRamadan: isRamadan,
  );

  titleController.text = titleController.text.isNotEmpty
      ? titleController.text
      : _generatedTitle(
          kind: kind,
          selectedCourseOption: selectedCourseOption,
          courseOptions: courseOptions,
          item: item,
        );

  String courseCodeValue() {
    if (courseOptions.isNotEmpty) {
      return selectedCourseOption?.courseCode.trim().toUpperCase() ?? '';
    }
    return courseCodeController.text.trim().toUpperCase();
  }

  String generatedTitle([String? courseCode]) {
    return _generatedTitle(
      kind: kind,
      selectedCourseOption: selectedCourseOption,
      courseOptions: courseOptions,
      item: item,
      courseCode: courseCode,
    );
  }

  return showBracuBottomSheet<SchedulePlannerDraft>(
    context,
    title: item == null ? 'Add Item' : 'Edit Item',
    initialChildSize: 0.88,
    builder: (sheetContext, textPrimary, textSecondary) {
      return StatefulBuilder(
        builder: (context, setState) {
          Future<void> pickDueDate() async {
            final picked = await showDatePicker(
              context: context,
              initialDate: dueAt,
              firstDate: DateTime.now().subtract(const Duration(days: 1)),
              lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
            );
            if (picked == null || !context.mounted) return;
            setState(() {
              dueAt = DateTime(
                picked.year,
                picked.month,
                picked.day,
                dueAt.hour,
                dueAt.minute,
              );
            });
          }

          Future<void> pickDueTime() async {
            final picked = await showTimePicker(
              context: context,
              initialTime: TimeOfDay.fromDateTime(dueAt),
            );
            if (picked == null || !context.mounted) return;
            setState(() {
              dueAt = DateTime(
                dueAt.year,
                dueAt.month,
                dueAt.day,
                picked.hour,
                picked.minute,
              );
            });
          }

          Future<void> pickTitleTemplate() async {
            final template = await showBracuSelectSheet<_TitleTemplate>(
              context,
              title: 'Title Template',
              options: _titleTemplates(courseOptions: courseOptions, item: item)
                  .map(
                    (template) => BracuSelectOption<_TitleTemplate>(
                      value: template,
                      label: _titleTemplateLabel(template),
                      showLeadingIcon: false,
                    ),
                  )
                  .toList(),
              selectedValue: _currentTemplate(
                courseOptions: courseOptions,
                item: item,
                selectedCourseOption: selectedCourseOption,
                kind: kind,
                titleValue: titleController.text.trim(),
                courseCodeValue: courseCodeValue(),
              ),
            );
            if (template == null || !context.mounted) return;
            setState(() {
              selectedCourseOption = template.courseOption;
              kind = template.kind;
              titleController.text = _titleTemplateLabel(template);
            });
          }

          void save() {
            final reminderAt = useReminder
                ? dueAt.subtract(Duration(minutes: reminderMinutesBefore))
                : null;
            final courseCode = courseCodeValue();
            final title = titleController.text.trim().isEmpty
                ? generatedTitle(courseCode)
                : titleController.text.trim();
            if (courseCode.isEmpty) {
              showAppSnackBar(context, 'Select a course');
              return;
            }
            Navigator.of(context).pop((
              kind: kind,
              title: title,
              courseCode: courseCode,
              dueAt: dueAt,
              useReminder: useReminder,
              reminderAt: reminderAt,
              notes: notesController.text.trim(),
              isDone: isDone,
            ));
          }

          void setReminderEnabled(bool value) {
            setState(() {
              useReminder = value;
              if (value && reminderMinutesBefore < 5) {
                reminderMinutesBefore = 5;
              }
            });
          }

          void decreaseReminderMinutes() {
            setState(() {
              if (reminderMinutesBefore > 5) {
                reminderMinutesBefore -= 5;
              }
            });
          }

          void increaseReminderMinutes() {
            setState(() {
              reminderMinutesBefore += 5;
            });
          }

          return ListView(
            controller: bracuBottomSheetScrollController(context),
            padding: const EdgeInsets.only(bottom: 4),
            children: [
              TextField(
                controller: titleController,
                onChanged: (_) {
                  final parsed = _parseTitle(
                    titleController.text.trim(),
                    courseOptions: courseOptions,
                  );
                  if (parsed != null) {
                    selectedCourseOption = parsed.courseOption;
                    kind = parsed.kind;
                  }
                  setState(() {});
                },
                decoration: InputDecoration(
                  labelText: 'Title',
                  border: const OutlineInputBorder(),
                  isDense: true,
                  suffixIcon: IconButton(
                    tooltip: 'Select title template',
                    onPressed: pickTitleTemplate,
                    icon: const Icon(Icons.filter_list_rounded),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: pickDueDate,
                      child: Text(DateFormat('dd MMM yyyy').format(dueAt)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: pickDueTime,
                      child: Text(DateFormat('hh:mm a').format(dueAt)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Reminder'),
                value: useReminder,
                onChanged: setReminderEnabled,
              ),
              if (useReminder) ...[
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: BracuPalette.primary.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: BracuPalette.primary.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    children: [
                      InkWell(
                        onTap: decreaseReminderMinutes,
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: BracuPalette.primary.withValues(alpha: 0.12),
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
                          child: Column(
                            children: [
                              Text(
                                '$reminderMinutesBefore min before',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: BracuPalette.textPrimary(context),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                DateFormat('dd MMM yyyy, hh:mm a').format(
                                  dueAt.subtract(
                                    Duration(minutes: reminderMinutesBefore),
                                  ),
                                ),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: BracuPalette.textSecondary(context),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      InkWell(
                        onTap: increaseReminderMinutes,
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: BracuPalette.primary.withValues(alpha: 0.12),
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
              ],
              const SizedBox(height: 12),
              TextField(
                controller: notesController,
                minLines: 2,
                maxLines: 2,
                maxLength: 500,
                decoration: const InputDecoration(
                  labelText: 'Write your notes...',
                  border: OutlineInputBorder(),
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  counterText: '',
                ),
              ),
              if (item != null) ...[
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Done'),
                  value: isDone,
                  onChanged: (value) {
                    setState(() {
                      isDone = value;
                    });
                  },
                ),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: save,
                  icon: const Icon(Icons.save_rounded),
                  label: const Text('Save'),
                ),
              ),
            ],
          );
        },
      );
    },
  ).whenComplete(() {
    titleController.dispose();
    courseCodeController.dispose();
    notesController.dispose();
  });
}

List<SchedulePlannerCourseOption> _courseOptionsForDropdown({
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
    if (seen.add(_courseOptionIdentity(next))) {
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
    if (seen.add(_courseOptionIdentity(current))) {
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

String _courseOptionIdentity(SchedulePlannerCourseOption option) {
  return '${option.courseCode}|${option.sectionName}';
}

SchedulePlannerCourseOption? _selectDefaultCourseOption(
  List<SchedulePlannerCourseOption> options, {
  required bool isRamadan,
}) {
  if (options.isEmpty) return null;

  final now = DateTime.now();
  SchedulePlannerCourseOption? bestOption;
  DateTime? bestOccurrence;

  for (final option in options) {
    final occurrence = _bestOccurrenceForOption(
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

  return bestOption ?? options.first;
}

DateTime? _bestOccurrenceForOption(
  SchedulePlannerCourseOption option, {
  required DateTime now,
  required bool isRamadan,
}) {
  DateTime? best;
  final nowMinutes = now.hour * 60 + now.minute;
  for (final schedule in option.classSchedules) {
    final occurrence = _nextOccurrence(
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

DateTime? _nextOccurrence({
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

SchedulePlannerCourseOption? _findCourseOption(
  List<SchedulePlannerCourseOption> options,
  String courseCode,
) {
  for (final option in options) {
    if (option.courseCode == courseCode) {
      return option;
    }
  }
  return options.isNotEmpty ? options.first : null;
}

List<_TitleTemplate> _titleTemplates({
  required List<SchedulePlannerCourseOption> courseOptions,
  required SchedulePlannerItem? item,
}) {
  final templates = <_TitleTemplate>[];
  final kinds = const ['quiz', 'assignment', 'reminder'];
  for (final course in _courseOptionsForDropdown(
    courseOptions: courseOptions,
    item: item,
  )) {
    for (final nextKind in kinds) {
      templates.add((courseOption: course, kind: nextKind));
    }
  }
  return templates;
}

_TitleTemplate? _currentTemplate({
  required List<SchedulePlannerCourseOption> courseOptions,
  required SchedulePlannerItem? item,
  required SchedulePlannerCourseOption? selectedCourseOption,
  required String kind,
  required String titleValue,
  required String courseCodeValue,
}) {
  final parsed = _parseTitle(titleValue, courseOptions: courseOptions);
  if (parsed != null) return parsed;
  final courseOption =
      selectedCourseOption ??
      _findCourseOption(
        _courseOptionsForDropdown(courseOptions: courseOptions, item: item),
        courseCodeValue,
      );
  if (courseOption == null) return null;
  return (courseOption: courseOption, kind: kind);
}

_TitleTemplate? _parseTitle(
  String value, {
  required List<SchedulePlannerCourseOption> courseOptions,
}) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;
  final parts = trimmed.split('•').map((part) => part.trim()).toList();
  if (parts.length < 2) return null;

  final kind = _matchKind(parts.last);
  if (kind == null) return null;

  final courseLabel = parts.take(parts.length - 1).join(' • ').trim();
  final courseOption = _findCourseOptionByLabel(
    courseLabel,
    courseOptions: courseOptions,
  );
  if (courseOption == null) return null;

  return (courseOption: courseOption, kind: kind);
}

String? _matchKind(String value) {
  final normalized = value.trim().toLowerCase();
  for (final kind in const ['quiz', 'assignment', 'reminder']) {
    if (normalized == kind) return kind;
  }
  return null;
}

SchedulePlannerCourseOption? _findCourseOptionByLabel(
  String label, {
  required List<SchedulePlannerCourseOption> courseOptions,
}) {
  final normalized = label.trim();
  for (final option in _courseOptionsForDropdown(
    courseOptions: courseOptions,
    item: null,
  )) {
    if (_courseOptionLabel(option) == normalized ||
        option.courseCode == normalized) {
      return option;
    }
  }
  return null;
}

String _courseOptionLabel(SchedulePlannerCourseOption option) {
  return option.sectionName.isEmpty
      ? option.courseCode
      : '${option.courseCode} • ${option.sectionName}';
}

String _titleTemplateLabel(_TitleTemplate template) {
  return '${_courseOptionLabel(template.courseOption)} • ${_kindLabel(template.kind)}';
}

String _generatedTitle({
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
  final sectionName = _selectedSectionName(
    code,
    courseOptions: courseOptions,
    selectedCourseOption: selectedCourseOption,
  );
  final kindLabel = _kindLabel(kind);
  if (code.isEmpty) return kindLabel;
  final courseLabel = sectionName.isEmpty ? code : '$code • $sectionName';
  return '$courseLabel • $kindLabel';
}

String _selectedSectionName(
  String courseCode, {
  required List<SchedulePlannerCourseOption> courseOptions,
  required SchedulePlannerCourseOption? selectedCourseOption,
}) {
  if (courseCode.isEmpty) return '';
  if (selectedCourseOption != null &&
      selectedCourseOption.courseCode.trim().toUpperCase() == courseCode) {
    return selectedCourseOption.sectionName.trim();
  }
  final matched = _findCourseOption(
    _courseOptionsForDropdown(courseOptions: courseOptions, item: null),
    courseCode,
  );
  return matched?.sectionName.trim() ?? '';
}

String _kindLabel(String kind) {
  switch (kind) {
    case 'quiz':
      return 'Quiz';
    case 'assignment':
      return 'Assignment';
    case 'reminder':
      return 'Reminder';
    default:
      return 'Item';
  }
}

String schedulePlannerFormatKind(String kind) {
  return _kindLabel(kind);
}

String schedulePlannerFormatDueDate(DateTime dueAt) {
  return DateFormat('dd MMM, hh:mm a').format(dueAt);
}

String schedulePlannerFormatReminder(DateTime reminderAt) {
  return DateFormat('dd MMM, hh:mm a').format(reminderAt);
}

IconData schedulePlannerKindIcon(String kind) {
  switch (kind) {
    case 'quiz':
      return Icons.quiz_outlined;
    case 'assignment':
      return Icons.assignment_outlined;
    case 'reminder':
      return Icons.alarm_outlined;
    default:
      return Icons.event_available_outlined;
  }
}

Color schedulePlannerKindColor(String kind) {
  switch (kind) {
    case 'quiz':
      return const Color(0xFF7C56FF);
    case 'assignment':
      return const Color(0xFF1E6BE3);
    case 'reminder':
      return const Color(0xFF22B573);
    default:
      return const Color(0xFF5B8DEF);
  }
}
