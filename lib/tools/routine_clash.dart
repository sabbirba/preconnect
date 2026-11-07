import 'package:preconnect/api/seat_status.dart';
import 'package:preconnect/tools/time_utils.dart';

class RoutineBlock {
  const RoutineBlock({
    required this.weekday,
    required this.start,
    required this.end,
  });

  final int weekday;
  final int start;
  final int end;

  bool overlaps(RoutineBlock other) =>
      weekday == other.weekday && start < other.end && other.start < end;

  @override
  bool operator ==(Object other) =>
      other is RoutineBlock &&
      weekday == other.weekday &&
      start == other.start &&
      end == other.end;

  @override
  int get hashCode => Object.hash(weekday, start, end);
}

List<RoutineBlock> routineBlocks(Iterable<SeatStatusClassSchedule> schedules) {
  final blocks = <RoutineBlock>{};
  for (final schedule in schedules) {
    final weekday = AppTime.weekdayFromName(schedule.day);
    final start = AppTime.toMinutes(schedule.startTime);
    final end = AppTime.toMinutes(schedule.endTime);
    if (weekday == null || start == null || end == null || end <= start) {
      continue;
    }
    blocks.add(RoutineBlock(weekday: weekday, start: start, end: end));
  }
  return blocks.toList();
}

List<RoutineBlock> sectionBlocks(SeatStatusDetailsResponse section) {
  return routineBlocks(<SeatStatusClassSchedule>[
    ...section.sectionSchedule.classSchedules,
    ...section.labSchedules,
  ]);
}

bool blocksClash(List<RoutineBlock> a, List<RoutineBlock> b) {
  for (final left in a) {
    for (final right in b) {
      if (left.overlaps(right)) return true;
    }
  }
  return false;
}

String planCourseKey(String courseCode) =>
    courseCode.replaceAll(RegExp(r'\s+'), '').toUpperCase();

SeatStatusDetailsResponse? bestSectionFor(
  List<SeatStatusDetailsResponse> options,
  List<SeatStatusDetailsResponse> picked,
) {
  final pickedBlocks = <RoutineBlock>[
    for (final section in picked) ...sectionBlocks(section),
  ];
  final usedDays = {for (final block in pickedBlocks) block.weekday};
  SeatStatusDetailsResponse? best;
  var bestNewDays = 0;
  for (final option in options) {
    if (option.remainingSeats <= 0) continue;
    final blocks = sectionBlocks(option);
    if (blocksClash(blocks, pickedBlocks)) continue;
    final newDays = {
      for (final block in blocks)
        if (!usedDays.contains(block.weekday)) block.weekday,
    }.length;
    final current = best;
    if (current == null ||
        newDays < bestNewDays ||
        (newDays == bestNewDays &&
            option.remainingSeats > current.remainingSeats)) {
      best = option;
      bestNewDays = newDays;
    }
  }
  return best;
}
