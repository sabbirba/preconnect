import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:gap/gap.dart';
import 'package:preconnect/api/planner_state.dart';
import 'package:preconnect/api/seat_pins.dart';
import 'package:preconnect/api/seat_status.dart';
import 'package:preconnect/pages/shared_widgets/faculty_sheet.dart';
import 'package:preconnect/pages/shared_widgets/routine_sheet.dart';
import 'package:preconnect/pages/shared_widgets/seat_card.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/routine_clash.dart';

Future<void> togglePlannedSection(
  BuildContext context,
  SeatCardData card,
) async {
  final planner = PlannerController.instance;
  final planned = planner.isPlanned(card.courseCode, card.sectionId);
  final label = '${card.courseCode} Section ${card.sectionName}';
  try {
    if (planned) {
      await planner.removeFromWishlist(card.courseCode);
    } else {
      await planner.plan(card.courseCode, card.sectionId);
    }
  } catch (_) {
    if (context.mounted) showAppSnackBar(context, 'Could not save. Try again.');
    return;
  }
  if (!context.mounted) return;
  showAppSnackBar(
    context,
    planned ? '$label removed from planner' : '$label added to planner',
  );
}

Future<void> toggleSeatAlert(BuildContext context, SeatCardData card) async {
  final result = await SeatPins.instance.toggle(
    card.sectionId,
    courseCode: card.courseCode,
    sectionName: card.sectionName,
  );
  if (!context.mounted) return;
  showAppSnackBar(
    context,
    seatPinMessage(
      result,
      courseCode: card.courseCode,
      sectionName: card.sectionName,
    ),
  );
}

Set<int> plannerConflictIds(
  Iterable<SeatCardData> cards,
  List<SeatStatusDetailsResponse> picked,
) {
  if (picked.isEmpty) return const <int>{};
  final plannedBlocks = [
    for (final section in picked)
      (planCourseKey(section.courseCode), sectionBlocks(section)),
  ];
  final conflicts = <int>{};
  for (final card in cards) {
    final course = planCourseKey(card.courseCode);
    final blocks = routineBlocks([...card.classSchedule, ...card.labSchedule]);
    for (final (plannedCourse, planned) in plannedBlocks) {
      if (plannedCourse != course && blocksClash(blocks, planned)) {
        conflicts.add(card.sectionId);
        break;
      }
    }
  }
  return conflicts;
}

class PlannerConflictCache {
  Object? _key;
  Set<int> _ids = const <int>{};

  Set<int> ids(
    List<SeatCardData> cards,
    List<SeatStatusDetailsResponse> picked,
  ) {
    if (picked.isEmpty || cards.isEmpty) return const <int>{};
    final key = (
      identityHashCode(cards),
      Object.hashAll(cards.map((card) => card.sectionId)),
      Object.hashAll(picked.map((section) => section.sectionId)),
    );
    if (key == _key) return _ids;
    _key = key;
    _ids = plannerConflictIds(cards, picked);
    return _ids;
  }
}

void loadPlannerAndPins(BuildContext context) {
  unawaited(
    _loadOrNotify(
      context,
      PlannerController.instance.load,
      'Could not load your planner.',
    ),
  );
  unawaited(
    _loadOrNotify(
      context,
      SeatPins.instance.load,
      'Could not load seat alerts.',
    ),
  );
}

Future<void> _loadOrNotify(
  BuildContext context,
  Future<void> Function() load,
  String failureMessage,
) async {
  try {
    await load();
  } catch (_) {
    if (context.mounted) showAppSnackBar(context, failureMessage);
  }
}

void showSeatFacultySchedule(
  BuildContext context, {
  required Iterable<SeatCardData> cards,
  required String facultyInitial,
  String? staffName,
  bool isRamadan = false,
}) {
  final initial = facultyInitial.trim().toUpperCase();
  if (initial.isEmpty || initial == 'TBA') return;
  final items = <FacultyScheduleItem>[
    for (final card in cards)
      if (card.facultyInitial.trim().toUpperCase() == initial) ...[
        for (final schedule in card.classSchedule)
          FacultyScheduleItem(
            courseCode: card.courseCode,
            sectionName: card.sectionName,
            day: schedule.day,
            startTime: schedule.startTime,
            endTime: schedule.endTime,
            roomNumber: card.room,
            consumedSeat: card.consumed,
            courseType: card.courseType,
          ),
        for (final schedule in card.labSchedule)
          FacultyScheduleItem(
            courseCode: card.courseCode,
            sectionName: card.sectionName,
            day: schedule.day,
            startTime: schedule.startTime,
            endTime: schedule.endTime,
            roomNumber: card.labRoom.isNotEmpty ? card.labRoom : card.room,
            consumedSeat: card.consumed,
            courseType: 'Lab',
          ),
      ],
  ];
  showFacultyScheduleSheet(
    context,
    facultyInitial: facultyInitial,
    staffName: staffName,
    items: items,
    isRamadan: isRamadan,
  );
}

class PlannerSeatCard extends StatelessWidget {
  const PlannerSeatCard({
    super.key,
    required this.item,
    required this.conflictIds,
    required this.onTap,
    this.active = true,
    this.enrolled = false,
    this.footer = const <Widget>[],
  });

  final SeatCardData item;
  final Set<int> conflictIds;
  final VoidCallback onTap;
  final bool active;
  final bool enrolled;
  final List<Widget> footer;

  @override
  Widget build(BuildContext context) {
    final planned =
        active &&
        PlannerController.instance.isPlanned(item.courseCode, item.sectionId);
    final conflict = active && conflictIds.contains(item.sectionId);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SeatCard(
        item: item,
        footer: footer,
        highlighted: enrolled || planned || conflict,
        highlightColor: conflict ? AppPalette.warning : AppPalette.accent,
        onPinTap: active ? () => toggleSeatAlert(context, item) : null,
        pinned: active && SeatPins.instance.contains(item.sectionId),
        planned: planned,
        onPlanTap: active ? () => togglePlannedSection(context, item) : null,
        onTap: onTap,
      ),
    );
  }
}

class PlannerScheduleButton extends StatelessWidget {
  const PlannerScheduleButton({
    super.key,
    required this.picked,
    required this.clashingIds,
    required this.isRamadan,
  });

  final List<SeatStatusDetailsResponse> picked;
  final Set<int> clashingIds;
  final bool isRamadan;

  @override
  Widget build(BuildContext context) {
    if (picked.isEmpty) return const SizedBox.shrink();
    final textPrimary = AppPalette.textPrimary(context);
    return Positioned(
      left: 0,
      right: 0,
      bottom: 20,
      child: Center(
        child: Material(
          color: AppPalette.card(context),
          elevation: 6,
          shape: StadiumBorder(
            side: BorderSide(color: AppPalette.accent.withValues(alpha: 0.6)),
          ),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: () => showRoutineSheet(
              context,
              sections: picked,
              clashingIds: {
                for (final section in picked)
                  if (clashingIds.contains(section.sectionId))
                    section.sectionId,
              },
              isRamadan: isRamadan,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.calendar_month_rounded,
                    size: 18,
                    color: AppPalette.accent,
                  ),
                  const Gap(8),
                  Text(
                    'Schedule',
                    style: TextStyle(
                      color: textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Gap(8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppPalette.accent.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${picked.length}',
                      style: TextStyle(
                        color: textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
