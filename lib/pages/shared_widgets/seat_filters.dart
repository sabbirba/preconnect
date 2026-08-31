import 'package:flutter/material.dart';
import 'package:preconnect/api/seat_status.dart';
import 'package:preconnect/model/seat_timetable.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/time_utils.dart';

const List<String> seatFilterModes = <String>['Labs', 'Theory'];
const List<String> seatFilterWeekdays = <String>[
  'SATURDAY',
  'SUNDAY',
  'MONDAY',
  'TUESDAY',
  'WEDNESDAY',
  'THURSDAY',
  'FRIDAY',
];

List<SeatTimetable> sortedSeatFilterTimes(Iterable<SeatTimetable> source) {
  final times = source.toSet().toList();
  times.sort((a, b) {
    final start = (BracuTime.toMinutes(a.startTime) ?? 24 * 60).compareTo(
      BracuTime.toMinutes(b.startTime) ?? 24 * 60,
    );
    if (start != 0) return start;
    return (BracuTime.toMinutes(a.endTime) ?? 24 * 60).compareTo(
      BracuTime.toMinutes(b.endTime) ?? 24 * 60,
    );
  });
  return times;
}

bool matchesSeatFilters({
  required bool availableOnly,
  required int remaining,
  required String mode,
  required bool hasLabSection,
  required List<SeatStatusClassSchedule> theorySchedules,
  required List<SeatStatusClassSchedule> labSchedules,
  required String day,
  required SeatTimetable time,
}) {
  if (availableOnly && remaining <= 0) return false;
  final schedules = switch (mode) {
    'Labs' => hasLabSection ? labSchedules : const <SeatStatusClassSchedule>[],
    'Theory' => theorySchedules,
    _ => <SeatStatusClassSchedule>[...theorySchedules, ...labSchedules],
  };
  if (day.isEmpty && time.isEmpty) {
    return mode.isEmpty || schedules.isNotEmpty;
  }
  return schedules.any(
    (schedule) =>
        (day.isEmpty || normalizeWeekday(schedule.day) == day) &&
        (time.isEmpty || schedule.toTimetable() == time),
  );
}

class SeatFilterBar extends StatelessWidget {
  const SeatFilterBar({
    super.key,
    required this.availableOnly,
    required this.mode,
    required this.day,
    required this.time,
    required this.times,
    required this.onAvailableChanged,
    required this.onModeChanged,
    required this.onDayChanged,
    required this.onTimeChanged,
  });

  final bool availableOnly;
  final String mode;
  final String day;
  final SeatTimetable time;
  final List<SeatTimetable> times;
  final ValueChanged<bool> onAvailableChanged;
  final ValueChanged<String> onModeChanged;
  final ValueChanged<String> onDayChanged;
  final ValueChanged<SeatTimetable> onTimeChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: [
          BracuSelectChip(
            icon: Icons.event_available_outlined,
            label: 'Available',
            selected: availableOnly,
            compact: true,
            borderRadius: 16,
            showArrow: false,
            onTap: () => onAvailableChanged(!availableOnly),
          ),
          BracuSelectDropdownChip<String>(
            icon: Icons.explore,
            label: mode.isEmpty ? 'Labs + Theory' : mode,
            selected: mode.isNotEmpty,
            compact: true,
            borderRadius: 999,
            title: 'Change Mode',
            subtitle: 'Show labs, theories, or both',
            selectedValue: mode,
            options: <BracuSelectOption<String>>[
              const BracuSelectOption<String>(
                value: '',
                label: 'Labs + Theory',
                icon: Icons.all_inclusive_rounded,
              ),
              ...seatFilterModes.map(
                (value) => BracuSelectOption<String>(
                  value: value,
                  label: value,
                  icon: value == 'Labs'
                      ? Icons.science_outlined
                      : Icons.menu_book_outlined,
                ),
              ),
            ],
            onSelected: onModeChanged,
          ),
          BracuSelectDropdownChip<String>(
            icon: Icons.calendar_today_outlined,
            label: day.isEmpty ? 'Any Day' : formatWeekdayTitle(day),
            selected: day.isNotEmpty,
            compact: true,
            borderRadius: 999,
            title: 'Filter by Day',
            subtitle: 'Show sections on a specific weekday',
            selectedValue: day,
            options: <BracuSelectOption<String>>[
              const BracuSelectOption<String>(
                value: '',
                label: 'Any Day',
                icon: Icons.all_inclusive_rounded,
              ),
              ...seatFilterWeekdays.map(
                (value) => BracuSelectOption<String>(
                  value: value,
                  label: formatWeekdayTitle(value),
                  icon: Icons.calendar_today_outlined,
                ),
              ),
            ],
            onSelected: onDayChanged,
          ),
          BracuSelectDropdownChip<SeatTimetable>(
            icon: Icons.schedule_outlined,
            label: time.isEmpty ? 'Any Time' : time.label,
            selected: time.isNotEmpty,
            compact: true,
            borderRadius: 999,
            title: 'Filter by Time',
            subtitle: 'Show sections at a specific time',
            selectedValue: time,
            options: <BracuSelectOption<SeatTimetable>>[
              const BracuSelectOption<SeatTimetable>(
                value: SeatTimetable(startTime: '', endTime: ''),
                label: 'Any Time',
                icon: Icons.all_inclusive_rounded,
              ),
              ...times.map(
                (value) => BracuSelectOption<SeatTimetable>(
                  value: value,
                  label: value.label,
                  icon: Icons.schedule_outlined,
                ),
              ),
            ],
            onSelected: onTimeChanged,
          ),
        ],
      ),
    );
  }
}
