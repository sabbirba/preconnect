// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:preconnect/model/schedule_planner_item.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/pages/schedule_planner_sections/schedule_planner_shared.dart';
import 'package:preconnect/tools/ramadan_timing.dart';

Future<SchedulePlannerDraft?> showSchedulePlannerEditorSheet(
  BuildContext context, {
  required SchedulePlannerItem? item,
  required List<SchedulePlannerCourseOption> courseOptions,
  SchedulePlannerSetAlarmCallback? onSetAlarm,
  SchedulePlannerDeleteCallback? onDelete,
  SchedulePlannerToggleDoneCallback? onToggleDone,
}) async {
  final isRamadan = await RamadanTiming.isRamadan();
  var titleValue = item?.title.trim().isNotEmpty == true
      ? schedulePlannerNormalizeTitle(item!.title.trim())
      : '';
  var courseCodeValueText = item?.courseCode ?? '';
  var sectionNameValueText = item?.sectionName ?? '';
  var notesValue = item?.notes ?? '';
  var titleFieldVersion = 0;
  var kind = item != null && item.kind.isNotEmpty ? item.kind : 'quiz';
  var dueAt = item?.dueAt ?? DateTime.now().add(const Duration(days: 1));
  var reminderMinutesBefore = item?.reminderAt == null
      ? 60
      : dueAt.difference(item!.reminderAt!).inMinutes;
  if (reminderMinutesBefore < 5) {
    reminderMinutesBefore = 5;
  }
  var isDone = item?.isDone ?? false;

  final availableCourseOptions = schedulePlannerCourseOptionsForDropdown(
    courseOptions: courseOptions,
    item: item,
  );
  final initialCourseCode = item?.courseCode.trim().toUpperCase();
  final initialSectionName = item?.sectionName.trim() ?? '';
  SchedulePlannerCourseOption? selectedCourseOption =
      initialCourseCode != null && initialCourseCode.isNotEmpty
      ? schedulePlannerFindCourseOption(
          availableCourseOptions,
          initialCourseCode,
          preferredSectionName: initialSectionName,
        )
      : null;
  selectedCourseOption ??= schedulePlannerSelectDefaultCourseOption(
    availableCourseOptions,
    isRamadan: isRamadan,
  );

  var resolvedSectionName = schedulePlannerResolveSectionName(
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
      ? schedulePlannerInitialSuffix(
          item!.title.trim(),
          courseCode:
              selectedCourseOption?.courseCode.trim().toUpperCase() ??
              item.courseCode.trim().toUpperCase(),
          sectionName: resolvedSectionName.isNotEmpty
              ? resolvedSectionName
              : sectionNameValueText.trim(),
        )
      : schedulePlannerKindLabel(kind);

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
    if (schedulePlannerHasUsableSectionLabel(resolvedSectionName)) {
      return resolvedSectionName.trim();
    }
    final fallback = sectionNameValueText.trim();
    if (schedulePlannerHasUsableSectionLabel(fallback)) return fallback;
    return schedulePlannerResolveSectionName(
      courseCode: fixedCourseCode(),
      sectionName: fallback,
      title: item?.title.trim() ?? '',
      courseOptions: availableCourseOptions,
    );
  }

  final liveTitle = ValueNotifier<String>(
    item == null
        ? 'Add ${schedulePlannerKindLabel(kind)}'
        : 'Edit ${schedulePlannerKindLabel(kind)}',
  );

  void syncLiveTitle() {
    liveTitle.value = item == null
        ? 'Add ${schedulePlannerKindLabel(kind)}'
        : 'Edit ${schedulePlannerKindLabel(kind)}';
  }

  final result = await showBracuBottomSheet<SchedulePlannerDraft>(
    context,
    title: item == null
        ? 'Add ${schedulePlannerKindLabel(kind)}'
        : 'Edit ${schedulePlannerKindLabel(kind)}',
    liveTitle: liveTitle,
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
            final template =
                await showBracuSelectSheet<SchedulePlannerTitleTemplate>(
                  context,
                  title: 'Title Template',
                  options:
                      schedulePlannerTitleTemplates(
                            courseOptions: courseOptions,
                            item: item,
                          )
                          .map(
                            (template) =>
                                BracuSelectOption<SchedulePlannerTitleTemplate>(
                                  value: template,
                                  label: schedulePlannerTitleTemplateLabel(
                                    template,
                                  ),
                                  showLeadingIcon: false,
                                ),
                          )
                          .toList(),
                  selectedValue: schedulePlannerCurrentTemplateBySelection(
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
              titleValue = schedulePlannerKindLabel(template.kind);
              titleFieldVersion++;
              syncLiveTitle();
            });
          }

          void save() {
            final reminderAt = dueAt.subtract(
              Duration(minutes: reminderMinutesBefore),
            );
            final courseCode = fixedCourseCode();
            final sectionName = fixedSectionName();
            final titleSuffix = titleValue.trim().isEmpty
                ? schedulePlannerKindLabel(kind)
                : titleValue.trim();
            final title = schedulePlannerComposeTitle(
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
              dueAt: dueAt,
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
                  'planner_title_${titleFieldVersion}_${fixedCourseCode()}_${fixedSectionName()}',
                ),
                initialValue: titleValue,
                onChanged: (value) {
                  titleValue = value;
                  setState(() {});
                },
                decoration: InputDecoration(
                  labelText: 'Title',
                  prefixText:
                      '${fixedCourseCode().isEmpty ? 'Select course' : fixedCourseCode()} • ',
                  prefixStyle: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: BracuPalette.textSecondary(context),
                  ),
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
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final reminderAt = dueAt.subtract(
                      Duration(minutes: reminderMinutesBefore),
                    );
                    final courseCode = courseCodeValue();
                    final title = titleValue.trim().isEmpty
                        ? schedulePlannerGeneratedTitle(
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
                          ? Icons.radio_button_unchecked_rounded
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
