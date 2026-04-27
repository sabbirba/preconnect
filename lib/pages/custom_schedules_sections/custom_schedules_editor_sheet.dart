// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:preconnect/model/custom_schedule.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/pages/custom_schedules_sections/custom_schedules_shared.dart';
import 'package:preconnect/tools/ramadan_timing.dart';

Future<CustomSchedulesDraft?> showCustomSchedulesEditorSheet(
  BuildContext context, {
  required CustomSchedule? item,
  required List<CustomSchedulesCourseOption> courseOptions,
  CustomSchedulesSetAlarmCallback? onSetAlarm,
  CustomSchedulesDeleteCallback? onDelete,
  CustomSchedulesToggleDoneCallback? onToggleDone,
}) async {
  final isRamadan = await RamadanTiming.isRamadan();
  var titleValue = item?.title.trim().isNotEmpty == true
      ? personalSchedulesNormalizeTitle(item!.title.trim())
      : '';
  var courseCodeValueText = item?.courseCode ?? '';
  var sectionNameValueText = item?.sectionName ?? '';
  var notesValue = item?.notes ?? '';
  var titleFieldVersion = 0;
  var kind = item != null && item.kind.isNotEmpty ? item.kind : 'quiz';
  final existingStartTime = item?.startTime.toLocal();
  final existingEndTime = item?.endTime?.toLocal();
  final existingReminderAt = item?.reminderAt?.toLocal();
  var startTime =
      existingStartTime ?? DateTime.now().add(const Duration(days: 1));
  var endTime = existingEndTime;
  var reminderMinutesBefore = existingReminderAt == null
      ? 60
      : startTime.difference(existingReminderAt).inMinutes;
  if (reminderMinutesBefore < 5) {
    reminderMinutesBefore = 5;
  }
  var isDone = item?.isDone ?? false;

  final availableCourseOptions = personalSchedulesCourseOptionsForDropdown(
    courseOptions: courseOptions,
    item: item,
  );
  final initialCourseCode = item?.courseCode.trim().toUpperCase();
  final initialSectionName = item?.sectionName.trim() ?? '';
  CustomSchedulesCourseOption? selectedCourseOption =
      initialCourseCode != null && initialCourseCode.isNotEmpty
      ? personalSchedulesFindCourseOption(
          availableCourseOptions,
          initialCourseCode,
          preferredSectionName: initialSectionName,
        )
      : null;
  selectedCourseOption ??= personalSchedulesSelectDefaultCourseOption(
    availableCourseOptions,
    isRamadan: isRamadan,
  );

  String editableTitleSuffix(
    String rawTitle, {
    required String courseCode,
    required String sectionName,
  }) {
    final normalizedCode = courseCode.trim().toUpperCase();
    final normalizedSection = sectionName.trim();
    final tokens = rawTitle
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();

    while (tokens.isNotEmpty) {
      final first = tokens.first;
      if (normalizedCode.isNotEmpty && first.toUpperCase() == normalizedCode) {
        tokens.removeAt(0);
        continue;
      }
      if (normalizedSection.isNotEmpty && first == normalizedSection) {
        tokens.removeAt(0);
        continue;
      }
      break;
    }

    return tokens.join(' ').trim();
  }

  void applyDefaultClassScheduleTimes() {
    final courseOption = selectedCourseOption;
    if (courseOption == null || courseOption.classSchedules.isEmpty) return;
    final occurrence = personalSchedulesDefaultOccurrenceForOption(
      courseOption,
      isRamadan: isRamadan,
    );
    if (occurrence == null) return;
    startTime = occurrence.startTime;
    endTime = occurrence.endTime;
  }

  if (item == null) {
    applyDefaultClassScheduleTimes();
  }

  var resolvedSectionName = personalSchedulesResolveSectionName(
    courseCode:
        selectedCourseOption?.courseCode.trim().toUpperCase() ??
        initialCourseCode ??
        courseCodeValueText.trim().toUpperCase(),
    sectionName: selectedCourseOption?.sectionName.trim().isNotEmpty == true
        ? selectedCourseOption!.sectionName.trim()
        : initialSectionName,
    title: item?.title.trim() ?? '',
    courseOptions: availableCourseOptions,
  );

  titleValue = item?.title.trim().isNotEmpty == true
      ? editableTitleSuffix(
          item!.title.trim(),
          courseCode:
              selectedCourseOption?.courseCode.trim().toUpperCase() ??
              item.courseCode.trim().toUpperCase(),
          sectionName: resolvedSectionName.isNotEmpty
              ? resolvedSectionName
              : sectionNameValueText.trim(),
        )
      : personalSchedulesKindLabel(kind);

  String courseCodeValue() {
    if (courseOptions.isNotEmpty) {
      return selectedCourseOption?.courseCode.trim().toUpperCase() ?? '';
    }
    return courseCodeValueText.trim().toUpperCase();
  }

  String fixedCourseCode() {
    return courseCodeValue();
  }

  String fixedSectionName() {
    if (personalSchedulesHasUsableSectionLabel(resolvedSectionName)) {
      return resolvedSectionName.trim();
    }
    final fallback = sectionNameValueText.trim();
    if (personalSchedulesHasUsableSectionLabel(fallback)) return fallback;
    return personalSchedulesResolveSectionName(
      courseCode: fixedCourseCode(),
      sectionName: fallback,
      title: item?.title.trim() ?? '',
      courseOptions: availableCourseOptions,
    );
  }

  final liveTitle = ValueNotifier<String>(
    item == null
        ? 'Add ${personalSchedulesKindLabel(kind)}'
        : 'Edit ${personalSchedulesKindLabel(kind)}',
  );

  void syncLiveTitle() {
    liveTitle.value = item == null
        ? 'Add ${personalSchedulesKindLabel(kind)}'
        : 'Edit ${personalSchedulesKindLabel(kind)}';
  }

  final result = await showBracuBottomSheet<CustomSchedulesDraft>(
    context,
    title: item == null
        ? 'Add ${personalSchedulesKindLabel(kind)}'
        : 'Edit ${personalSchedulesKindLabel(kind)}',
    liveTitle: liveTitle,
    initialChildSize: 0.88,
    builder: (sheetContext, textPrimary, textSecondary) {
      return StatefulBuilder(
        builder: (context, setState) {
          Future<bool> pickDueDate() async {
            final picked = await showDatePicker(
              context: context,
              initialDate: startTime,
              firstDate: DateTime.now().subtract(const Duration(days: 1)),
              lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
            );
            if (picked == null || !context.mounted) return false;
            setState(() {
              startTime = DateTime(
                picked.year,
                picked.month,
                picked.day,
                startTime.hour,
                startTime.minute,
              );
              if (endTime != null) {
                endTime = DateTime(
                  picked.year,
                  picked.month,
                  picked.day,
                  endTime!.hour,
                  endTime!.minute,
                );
              }
            });
            return true;
          }

          Future<bool> pickStartTime() async {
            final picked = await showTimePicker(
              context: context,
              initialTime: TimeOfDay.fromDateTime(startTime),
            );
            if (picked == null || !context.mounted) return false;
            setState(() {
              startTime = DateTime(
                startTime.year,
                startTime.month,
                startTime.day,
                picked.hour,
                picked.minute,
              );
              if (endTime != null && endTime!.isBefore(startTime)) {
                endTime = startTime.add(const Duration(hours: 1));
              }
            });
            return true;
          }

          Future<bool> pickEndTime() async {
            final initial = endTime ?? startTime.add(const Duration(hours: 1));
            final picked = await showTimePicker(
              context: context,
              initialTime: TimeOfDay.fromDateTime(initial),
            );
            if (picked == null || !context.mounted) return false;
            final nextEndAt = DateTime(
              startTime.year,
              startTime.month,
              startTime.day,
              picked.hour,
              picked.minute,
            );
            if (nextEndAt.isBefore(startTime)) {
              showAppSnackBar(context, 'End time must be after start time');
              return false;
            }
            setState(() {
              endTime = nextEndAt;
            });
            return true;
          }

          Future<void> pickTitleTemplate() async {
            final template =
                await showBracuSelectSheet<CustomSchedulesTitleTemplate>(
                  context,
                  title: 'Title Template',
                  options:
                      personalSchedulesTitleTemplates(
                            courseOptions: courseOptions,
                            item: item,
                          )
                          .map(
                            (template) =>
                                BracuSelectOption<CustomSchedulesTitleTemplate>(
                                  value: template,
                                  label: personalSchedulesTitleTemplateLabel(
                                    template,
                                  ),
                                  showLeadingIcon: false,
                                ),
                          )
                          .toList(),
                  selectedValue: personalSchedulesCurrentTemplateBySelection(
                    courseOptions: courseOptions,
                    item: item,
                    selectedCourseOption: selectedCourseOption,
                    resolvedSectionName: resolvedSectionName,
                    kind: kind,
                  ),
                );
            if (template == null || !context.mounted) return;
            setState(() {
              selectedCourseOption = template.courseOption;
              resolvedSectionName = template.sectionName;
              kind = template.kind;
              titleValue = personalSchedulesKindLabel(template.kind);
              if (item == null) {
                final occurrence = personalSchedulesDefaultOccurrenceForOption(
                  template.courseOption,
                  isRamadan: isRamadan,
                );
                if (occurrence != null) {
                  startTime = occurrence.startTime;
                  endTime = occurrence.endTime;
                }
              }
              titleFieldVersion++;
              syncLiveTitle();
            });
          }

          void save() {
            if (endTime != null && endTime!.isBefore(startTime)) {
              showAppSnackBar(context, 'End time must be after start time');
              return;
            }
            final reminderAt = startTime.subtract(
              Duration(minutes: reminderMinutesBefore),
            );
            final courseCode = fixedCourseCode();
            final sectionName = fixedSectionName();
            final titleSuffix =
                editableTitleSuffix(
                  titleValue,
                  courseCode: courseCode,
                  sectionName: sectionName,
                ).trim().isEmpty
                ? personalSchedulesKindLabel(kind)
                : editableTitleSuffix(
                    titleValue,
                    courseCode: courseCode,
                    sectionName: sectionName,
                  );
            final title = personalSchedulesComposeTitle(
              courseCode: courseCode,
              sectionName: sectionName,
              suffix: titleSuffix,
            );
            if (courseCode.isEmpty) {
              showAppSnackBar(context, 'Select a course');
              return;
            }
            if (sectionName.isEmpty) {
              showAppSnackBar(context, 'Select a section');
              return;
            }
            Navigator.of(context).pop((
              kind: kind,
              title: title,
              courseCode: courseCode,
              sectionName: sectionName,
              startTime: startTime,
              endTime: endTime,
              useReminder: true,
              reminderAt: reminderAt,
              notes: notesValue.trim(),
              isDone: isDone,
            ));
          }

          Future<void> deleteItem() async {
            if (onDelete == null) return;
            Navigator.of(context).pop();
            await onDelete();
          }

          Future<void> toggleDoneStatus() async {
            if (onToggleDone == null) return;
            final nextDone = !isDone;
            setState(() {
              isDone = nextDone;
            });
            Navigator.of(context).pop();
            await onToggleDone(nextDone);
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
              TextFormField(
                key: ValueKey(
                  'my_title_${titleFieldVersion}_${fixedCourseCode()}_${fixedSectionName()}',
                ),
                initialValue: titleValue,
                minLines: 1,
                textAlignVertical: TextAlignVertical.center,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  height: 1,
                  color: BracuPalette.textPrimary(context),
                ),
                onChanged: (value) {
                  titleValue = value;
                  setState(() {});
                },
                decoration: InputDecoration(
                  labelText: 'Title',
                  prefixText:
                      '${fixedCourseCode().isEmpty ? 'Select course' : fixedCourseCode()} ',
                  prefixStyle: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    height: 1,
                    color: BracuPalette.textSecondary(context),
                  ),
                  border: const OutlineInputBorder(),
                  isDense: false,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 18,
                  ),
                  suffixIconConstraints: const BoxConstraints(
                    minWidth: 0,
                    minHeight: 0,
                  ),
                  suffixIcon: TextButton(
                    onPressed: pickTitleTemplate,
                    style: TextButton.styleFrom(
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      foregroundColor: BracuPalette.textSecondary(context),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          'Choose',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(width: 2),
                        Padding(
                          padding: EdgeInsets.only(top: 1),
                          child: Icon(
                            Icons.keyboard_arrow_down_rounded,
                            size: 17,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: pickDueDate,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(46),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: Text(
                    DateFormat('d MMM yyyy').format(startTime),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: pickStartTime,
                      child: Text(
                        'Start ${DateFormat('hh:mm a').format(startTime)}',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: pickEndTime,
                      child: Text(
                        endTime == null
                            ? 'End'
                            : 'End ${DateFormat('hh:mm a').format(endTime!)}',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
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
                                startTime.subtract(
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
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    final reminderAt = startTime.subtract(
                      Duration(minutes: reminderMinutesBefore),
                    );
                    final courseCode = courseCodeValue();
                    final title = titleValue.trim().isEmpty
                        ? personalSchedulesGeneratedTitle(
                            kind: kind,
                            selectedCourseOption: selectedCourseOption,
                            courseOptions: courseOptions,
                            item: item,
                            courseCode: courseCode,
                          )
                        : titleValue.trim();
                    if (courseCode.isEmpty) {
                      showAppSnackBar(context, 'Select a course');
                      return;
                    }
                    if (onSetAlarm == null) {
                      showAppSnackBar(context, 'Alarm action unavailable.');
                      return;
                    }
                    await onSetAlarm(
                      courseCode: courseCode,
                      title: title,
                      reminderAt: reminderAt,
                    );
                  },
                  icon: const Icon(Icons.notifications_active),
                  label: const Text('Set Alarm'),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                initialValue: notesValue,
                onChanged: (value) => notesValue = value,
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
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: save,
                  icon: const Icon(Icons.save_rounded),
                  label: const Text('Save'),
                ),
              ),
              if (item != null) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: toggleDoneStatus,
                    icon: Icon(
                      isDone
                          ? Icons.schedule_rounded
                          : Icons.check_circle_outline_rounded,
                    ),
                    label: Text(isDone ? 'Mark as Pending' : 'Mark as Done'),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: deleteItem,
                    icon: const Icon(Icons.delete_outline_rounded),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                    ),
                    label: const Text('Delete'),
                  ),
                ),
              ],
            ],
          );
        },
      );
    },
  );

  liveTitle.dispose();
  return result;
}

IconData personalSchedulesKindIcon(String kind) {
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

Color personalSchedulesKindColor(String kind) {
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
