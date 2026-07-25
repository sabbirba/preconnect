import 'package:flutter/material.dart';
import 'package:preconnect/model/section_info.dart' as section;
import 'package:preconnect/pages/shared_widgets/entry_card.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/time_utils.dart';

class FacultyScheduleItem {
  const FacultyScheduleItem({
    required this.courseCode,
    required this.sectionName,
    required this.day,
    required this.startTime,
    required this.endTime,
    required this.roomNumber,
    this.consumedSeat,
    required this.courseType,
  });

  final String courseCode;
  final String sectionName;
  final String day;
  final String startTime;
  final String endTime;
  final String roomNumber;
  final int? consumedSeat;
  final String courseType;
}

Future<void> showBracuFacultyScheduleSheet(
  BuildContext context, {
  required String facultyInitial,
  String? staffName,
  required List<FacultyScheduleItem> items,
  bool isRamadan = false,
}) async {
  if (facultyInitial.trim().isEmpty) return;

  final sortedItems = List<FacultyScheduleItem>.from(items);
  final dayOrder = {
    'SUNDAY': 0,
    'MONDAY': 1,
    'TUESDAY': 2,
    'WEDNESDAY': 3,
    'THURSDAY': 4,
    'FRIDAY': 5,
    'SATURDAY': 6,
  };
  sortedItems.sort((a, b) {
    final dayA = dayOrder[a.day.toUpperCase()] ?? 99;
    final dayB = dayOrder[b.day.toUpperCase()] ?? 99;
    if (dayA != dayB) {
      return dayA.compareTo(dayB);
    }
    final minA = BracuTime.toMinutes(a.startTime) ?? 0;
    final minB = BracuTime.toMinutes(b.startTime) ?? 0;
    return minA.compareTo(minB);
  });

  final displayTitle = staffName != null && staffName.trim().isNotEmpty
      ? '${staffName.trim()} (${facultyInitial.trim().toUpperCase()})'
      : facultyInitial.trim().toUpperCase();

  await showBracuBottomSheet<void>(
    context,
    title: displayTitle,
    subtitle: 'Faculty Schedule',
    builder: (sheetContext, textPrimary, textSecondary) {
      final dragController = bracuBottomSheetScrollController(sheetContext);
      if (sortedItems.isEmpty) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Center(
            child: Text(
              'No schedule found.',
              style: TextStyle(color: textSecondary),
            ),
          ),
        );
      }

      final grouped = <String, List<FacultyScheduleItem>>{};
      for (final entry in sortedItems) {
        final day = entry.day;
        grouped.putIfAbsent(day, () => []).add(entry);
      }

      final sortedDays = grouped.keys.toList()
        ..sort((a, b) {
          final dayA = dayOrder[a.toUpperCase()] ?? 99;
          final dayB = dayOrder[b.toUpperCase()] ?? 99;
          return dayA.compareTo(dayB);
        });

      return ListView.builder(
        controller: dragController,
        itemCount: sortedDays.length,
        itemBuilder: (context, dayIndex) {
          final day = sortedDays[dayIndex];
          final dayEntries = grouped[day]!;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 8),
                child: Text(
                  day,
                  style: TextStyle(
                    color: textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              ...dayEntries.map((entry) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: ScheduleEntryCard(
                    sectionName: entry.sectionName,
                    courseCode: entry.courseCode,
                    schedule: section.ClassSchedule(
                      startTime: entry.startTime,
                      endTime: entry.endTime,
                      day: entry.day,
                    ),
                    isRamadan: isRamadan,
                    roomNumber: entry.roomNumber,
                    faculties: facultyInitial,
                    consumedSeat: entry.consumedSeat,
                    courseType: entry.courseType,
                    wrapInCard: true,
                  ),
                );
              }),
            ],
          );
        },
      );
    },
  );
}
