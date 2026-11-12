import 'package:material_ui/material_ui.dart';
import 'package:preconnect/api/seat_status.dart';
import 'package:preconnect/model/seat_timetable.dart';
import 'package:preconnect/pages/shared_widgets/seat_card.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/time_utils.dart';

const List<String> seatFilterModes = <String>['Labs', 'Theory'];
const List<String> seatUpdateSorts = <String>['', 'Latest', 'Oldest'];

String nextSeatUpdateSort(String current) {
  final index = seatUpdateSorts.indexOf(current);
  return seatUpdateSorts[(index + 1) % seatUpdateSorts.length];
}

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
    final start = (AppTime.toMinutes(a.startTime) ?? 24 * 60).compareTo(
      AppTime.toMinutes(b.startTime) ?? 24 * 60,
    );
    if (start != 0) return start;
    return (AppTime.toMinutes(a.endTime) ?? 24 * 60).compareTo(
      AppTime.toMinutes(b.endTime) ?? 24 * 60,
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

class SeatFilters {
  const SeatFilters({
    this.query = '',
    this.availableOnly = false,
    this.mode = '',
    this.day = '',
    this.time = anyTime,
    this.hideConflicts = false,
    this.updateSort = '',
  });

  static const SeatTimetable anyTime = SeatTimetable(
    startTime: '',
    endTime: '',
  );
  static const SeatFilters cleared = SeatFilters();

  final String query;
  final bool availableOnly;
  final String mode;
  final String day;
  final SeatTimetable time;
  final bool hideConflicts;
  final String updateSort;

  bool get isActive =>
      query.isNotEmpty ||
      availableOnly ||
      hideConflicts ||
      updateSort.isNotEmpty ||
      day.isNotEmpty ||
      mode.isNotEmpty ||
      time.isNotEmpty;

  bool sameMatching(SeatFilters other) =>
      query == other.query &&
      availableOnly == other.availableOnly &&
      mode == other.mode &&
      day == other.day &&
      time == other.time;

  SeatFilters copyWith({
    String? query,
    bool? availableOnly,
    String? mode,
    String? day,
    SeatTimetable? time,
    bool? hideConflicts,
    String? updateSort,
  }) {
    return SeatFilters(
      query: query ?? this.query,
      availableOnly: availableOnly ?? this.availableOnly,
      mode: mode ?? this.mode,
      day: day ?? this.day,
      time: time ?? this.time,
      hideConflicts: hideConflicts ?? this.hideConflicts,
      updateSort: updateSort ?? this.updateSort,
    );
  }

  bool matches(SeatCardData card) {
    final q = query.trim().toLowerCase();
    if (q.isNotEmpty && !card.searchToken.contains(q)) return false;
    return matchesSeatFilters(
      availableOnly: availableOnly,
      remaining: card.remaining,
      mode: mode,
      hasLabSection: card.labSectionId != null,
      theorySchedules: card.classSchedule,
      labSchedules: card.labSchedule,
      day: day,
      time: time,
    );
  }

  List<SeatCardData> apply(
    Iterable<SeatCardData> cards, {
    Set<int> excludedIds = const <int>{},
    Set<int> conflictIds = const <int>{},
    bool Function(int sectionId)? pinnedFirst,
  }) {
    final result = [
      for (final card in cards)
        if (!excludedIds.contains(card.sectionId) &&
            !(hideConflicts && conflictIds.contains(card.sectionId)) &&
            matches(card))
          card,
    ];
    if (pinnedFirst != null) {
      sortSeatCardsByCourse(result, isPinned: pinnedFirst);
    }
    if (updateSort.isNotEmpty) {
      sortSeatCardsByUpdate(result, latest: updateSort == 'Latest');
    }
    return result;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SeatFilters &&
          sameMatching(other) &&
          hideConflicts == other.hideConflicts &&
          updateSort == other.updateSort;

  @override
  int get hashCode => Object.hash(
    query,
    availableOnly,
    mode,
    day,
    time,
    hideConflicts,
    updateSort,
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
    this.hideConflicts,
    this.onHideConflictsChanged,
    this.updateSort,
    this.onUpdateSortChanged,
    this.onReset,
  });

  factory SeatFilterBar.bound({
    Key? key,
    required SeatFilters filters,
    required Iterable<SeatCardData> cards,
    required ValueChanged<SeatFilters> onChanged,
    required VoidCallback onReset,
    bool plannerFilters = true,
  }) {
    return SeatFilterBar(
      key: key,
      availableOnly: filters.availableOnly,
      mode: filters.mode,
      day: filters.day,
      time: filters.time,
      times: sortedSeatFilterTimes(cards.expand((card) => card.timetables)),
      onAvailableChanged: (value) =>
          onChanged(filters.copyWith(availableOnly: value)),
      onModeChanged: (value) => onChanged(filters.copyWith(mode: value)),
      onDayChanged: (value) => onChanged(filters.copyWith(day: value)),
      onTimeChanged: (value) => onChanged(filters.copyWith(time: value)),
      hideConflicts: plannerFilters ? filters.hideConflicts : null,
      onHideConflictsChanged: (value) =>
          onChanged(filters.copyWith(hideConflicts: value)),
      updateSort: plannerFilters ? filters.updateSort : null,
      onUpdateSortChanged: (value) =>
          onChanged(filters.copyWith(updateSort: value)),
      onReset: filters.isActive ? onReset : null,
    );
  }

  final bool availableOnly;
  final String mode;
  final String day;
  final SeatTimetable time;
  final List<SeatTimetable> times;
  final ValueChanged<bool> onAvailableChanged;
  final ValueChanged<String> onModeChanged;
  final ValueChanged<String> onDayChanged;
  final ValueChanged<SeatTimetable> onTimeChanged;
  final bool? hideConflicts;
  final ValueChanged<bool>? onHideConflictsChanged;
  final String? updateSort;
  final ValueChanged<String>? onUpdateSortChanged;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: [
          AppSelectChip(
            icon: Icons.event_available_outlined,
            label: 'Available',
            selected: availableOnly,
            compact: true,
            borderRadius: 16,
            showArrow: false,
            onTap: () => onAvailableChanged(!availableOnly),
          ),
          if (hideConflicts case final hide?)
            AppSelectChip(
              icon: Icons.block_rounded,
              label: 'Hide Conflicts',
              selected: hide,
              compact: true,
              borderRadius: 16,
              showArrow: false,
              onTap: () => onHideConflictsChanged?.call(!hide),
            ),
          AppSelectDropdownChip<String>(
            icon: Icons.explore,
            label: mode.isEmpty ? 'Labs + Theory' : mode,
            selected: mode.isNotEmpty,
            compact: true,
            borderRadius: 999,
            title: 'Change Mode',
            subtitle: 'Show labs, theories, or both',
            selectedValue: mode,
            options: <AppSelectOption<String>>[
              const AppSelectOption<String>(
                value: '',
                label: 'Labs + Theory',
                icon: Icons.all_inclusive_rounded,
              ),
              ...seatFilterModes.map(
                (value) => AppSelectOption<String>(
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
          AppSelectDropdownChip<String>(
            icon: Icons.calendar_today_outlined,
            label: day.isEmpty ? 'Any Day' : formatWeekdayTitle(day),
            selected: day.isNotEmpty,
            compact: true,
            borderRadius: 999,
            title: 'Filter by Day',
            subtitle: 'Show sections on a specific weekday',
            selectedValue: day,
            options: <AppSelectOption<String>>[
              const AppSelectOption<String>(
                value: '',
                label: 'Any Day',
                icon: Icons.all_inclusive_rounded,
              ),
              ...seatFilterWeekdays.map(
                (value) => AppSelectOption<String>(
                  value: value,
                  label: formatWeekdayTitle(value),
                  icon: Icons.calendar_today_outlined,
                ),
              ),
            ],
            onSelected: onDayChanged,
          ),
          AppSelectDropdownChip<SeatTimetable>(
            icon: Icons.schedule_outlined,
            label: time.isEmpty ? 'Any Time' : time.label,
            selected: time.isNotEmpty,
            compact: true,
            borderRadius: 999,
            title: 'Filter by Time',
            subtitle: 'Show sections at a specific time',
            selectedValue: time,
            options: <AppSelectOption<SeatTimetable>>[
              const AppSelectOption<SeatTimetable>(
                value: SeatTimetable(startTime: '', endTime: ''),
                label: 'Any Time',
                icon: Icons.all_inclusive_rounded,
              ),
              ...times.map(
                (value) => AppSelectOption<SeatTimetable>(
                  value: value,
                  label: value.label,
                  icon: Icons.schedule_outlined,
                ),
              ),
            ],
            onSelected: onTimeChanged,
          ),
          if (updateSort case final sort?)
            AppSelectChip(
              icon: Icons.update_rounded,
              label: sort.isEmpty ? 'Normal' : sort,
              selected: sort.isNotEmpty,
              compact: true,
              borderRadius: 16,
              showArrow: false,
              onTap: () => onUpdateSortChanged?.call(nextSeatUpdateSort(sort)),
            ),
          if (onReset case final reset?)
            AppSelectChip(
              icon: Icons.restart_alt_rounded,
              label: 'Reset',
              selected: false,
              compact: true,
              borderRadius: 16,
              showArrow: false,
              onTap: reset,
            ),
        ],
      ),
    );
  }
}
