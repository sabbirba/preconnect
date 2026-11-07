import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:preconnect/api/seat_status.dart';
import 'package:preconnect/model/section_info.dart' as section_info;
import 'package:preconnect/pages/shared_widgets/entry_card.dart';
import 'package:preconnect/pages/shared_widgets/exam_card.dart';
import 'package:preconnect/pages/shared_widgets/seat_card.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/time_utils.dart';

const List<String> _weekdayNames = <String>[
  'MONDAY',
  'TUESDAY',
  'WEDNESDAY',
  'THURSDAY',
  'FRIDAY',
  'SATURDAY',
  'SUNDAY',
];

Future<void> showRoutineSheet(
  BuildContext context, {
  required List<SeatStatusDetailsResponse> sections,
  required Set<int> clashingIds,
  required bool isRamadan,
}) {
  final credits = sections.fold<int>(0, (sum, s) => sum + s.courseCredit);
  return showAppBottomSheet<void>(
    context,
    title: 'Planner Schedule',
    subtitle:
        '${sections.length} ${sections.length == 1 ? 'Course' : 'Courses'} • '
        '$credits ${credits == 1 ? 'Credit' : 'Credits'}',
    builder: (sheetContext, _, _) {
      return ListView(
        controller: bottomSheetScrollController(sheetContext),
        physics: const ClampingScrollPhysics(),
        children: [
          ...plannerClassSchedule(
            sections,
            clashingIds: clashingIds,
            isRamadan: isRamadan,
            today: DateTime.now(),
          ),
          ...plannerExamSchedule(sections),
          const Gap(8),
        ],
      );
    },
  );
}

DateTime nextDateForWeekday(String weekday, DateTime today) {
  final start = DateTime(today.year, today.month, today.day);
  final target = _weekdayNames.indexOf(weekday) + 1;
  if (target == 0) return start;
  return start.add(Duration(days: (target - start.weekday + 7) % 7));
}

List<Widget> plannerClassSchedule(
  List<SeatStatusDetailsResponse> sections, {
  required Set<int> clashingIds,
  required bool isRamadan,
  required DateTime today,
}) {
  final byDay = <String, List<(int, Widget)>>{};
  for (final section in sections) {
    final faculty = seatStatusFacultySummaryLabel(section.faculty);
    void add(SeatStatusClassSchedule slot, {required bool isLab}) {
      final day = normalizeWeekday(slot.day);
      if (!_weekdayNames.contains(day)) return;
      byDay.putIfAbsent(day, () => <(int, Widget)>[]).add((
        AppTime.toMinutes(slot.startTime) ?? 0,
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: ScheduleEntryCard(
            sectionName: section.sectionName,
            courseCode: section.courseCode,
            schedule: section_info.ClassSchedule(
              startTime: slot.startTime,
              endTime: slot.endTime,
              day: slot.day,
            ),
            isRamadan: isRamadan,
            roomNumber: isLab
                ? (section.labRoomName ?? section.roomNumber)
                : section.roomNumber,
            faculties: isLab ? (section.labFaculties ?? faculty) : faculty,
            consumedSeat: section.consumedSeat,
            courseType: isLab ? 'Lab' : section.courseType.trim(),
            highlighted: clashingIds.contains(section.sectionId),
            highlightColor: AppPalette.warning,
          ),
        ),
      ));
    }

    for (final slot in section.sectionSchedule.classSchedules) {
      add(slot, isLab: false);
    }
    for (final slot in section.labSchedules) {
      add(slot, isLab: true);
    }
  }
  final days = byDay.keys.toList()
    ..sort(
      (a, b) =>
          nextDateForWeekday(a, today).compareTo(nextDateForWeekday(b, today)),
    );
  return [
    for (final day in days)
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: AppSectionTitle(title: formatWeekdayTitle(day))),
              AppSectionTitle(
                title: formatLongDate(nextDateForWeekday(day, today)),
              ),
            ],
          ),
          const Gap(12),
          for (final (_, card)
              in byDay[day]!..sort((a, b) => a.$1.compareTo(b.$1)))
            card,
          const Gap(6),
        ],
      ),
  ];
}

List<Widget> plannerExamSchedule(List<SeatStatusDetailsResponse> sections) {
  List<SeatStatusDetailsResponse> withExam(
    String? Function(SeatStatusSchedule) date,
  ) {
    final list = [
      for (final section in sections)
        if ((date(section.sectionSchedule) ?? '').trim().isNotEmpty) section,
    ];
    list.sort((a, b) {
      final left = AppTime.parseDate(date(a.sectionSchedule));
      final right = AppTime.parseDate(date(b.sectionSchedule));
      if (left == null || right == null) return left == null ? 1 : -1;
      return left.compareTo(right);
    });
    return list;
  }

  final mids = withExam((schedule) => schedule.midExamDate);
  final finals = withExam((schedule) => schedule.finalExamDate);
  return [
    for (final (label, exams, isMid) in [
      ('Midterm', mids, true),
      ('Final', finals, false),
    ])
      for (final section in exams)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: AppSectionTitle(
                      title: ExamCard.formatExamDate(
                        isMid
                            ? section.sectionSchedule.midExamDate
                            : section.sectionSchedule.finalExamDate,
                      ),
                    ),
                  ),
                  const Gap(8),
                  AppSectionTitle(
                    title: label,
                    color: ExamCard.typeColor(isFinal: !isMid),
                  ),
                ],
              ),
              const Gap(8),
              ExamCard(
                courseCode: section.courseCode,
                sectionName: section.sectionName,
                startTime: isMid
                    ? section.sectionSchedule.midExamStartTime
                    : section.sectionSchedule.finalExamStartTime,
                endTime: isMid
                    ? section.sectionSchedule.midExamEndTime
                    : section.sectionSchedule.finalExamEndTime,
                faculties: seatStatusFacultySummaryLabel(section.faculty),
                consumedSeat: section.consumedSeat,
                isFinal: !isMid,
              ),
            ],
          ),
        ),
  ];
}
