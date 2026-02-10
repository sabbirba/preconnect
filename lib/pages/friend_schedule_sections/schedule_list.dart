import 'package:flutter/material.dart';
import 'package:preconnect/model/friend_schedule.dart';
import 'package:preconnect/pages/friend_schedule_sections/friend_header.dart';
import 'package:preconnect/pages/shared_widgets/section_badge.dart';
import 'package:preconnect/pages/ui_kit.dart';

class FriendScheduleItem {
  const FriendScheduleItem({required this.encoded, required this.friend});

  final String encoded;
  final FriendSchedule friend;
}

class FriendScheduleSection extends StatelessWidget {
  const FriendScheduleSection({
    super.key,
    required this.item,
    required this.onDelete,
  });

  final FriendScheduleItem item;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final friend = item.friend;
    final grouped = _groupByDay(friend);
    final nextKey = _pickNextEntryKey(friend);
    final orderedDays = _orderedDays(grouped.keys.toList());

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FriendHeaderCard(friend: friend, onDelete: onDelete),
          const SizedBox(height: 12),
          if (grouped.isEmpty)
            BracuCard(
              child: Text(
                'No schedule shared.',
                style: TextStyle(color: BracuPalette.textSecondary(context)),
              ),
            )
          else
            ...orderedDays.map((day) {
              final entries = grouped[day]!;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  BracuSectionTitle(title: formatWeekdayTitle(day)),
                  const SizedBox(height: 10),
                  ...entries.map((entry) {
                    final isHighlighted =
                        nextKey != null && _entryKey(entry) == nextKey;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: BracuCard(
                        isHighlighted: isHighlighted,
                        highlightColor: BracuPalette.primary,
                        child: Row(
                          children: [
                            SectionBadge(
                              label: formatSectionBadge(entry.sectionName),
                              color: BracuPalette.primary,
                              fontSize: 12,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 7,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    entry.courseCode,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    formatTimeRange(
                                      entry.startTime,
                                      entry.endTime,
                                    ),
                                    style: TextStyle(
                                      color: BracuPalette.textSecondary(
                                        context,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 4,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    entry.roomNumber?.toString() ?? '--',
                                    textAlign: TextAlign.right,
                                    style: TextStyle(
                                      color: BracuPalette.textPrimary(context),
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  if (entry.faculties != null &&
                                      entry.faculties!.trim().isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      entry.faculties!,
                                      textAlign: TextAlign.right,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: BracuPalette.textSecondary(
                                          context,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 6),
                ],
              );
            }),
          if (grouped.isNotEmpty) ...[
            const SizedBox(height: 6),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _FriendScheduleEntry {
  const _FriendScheduleEntry({
    required this.day,
    required this.startTime,
    required this.endTime,
    required this.courseCode,
    required this.sectionName,
    required this.roomNumber,
    required this.faculties,
  });

  final String day;
  final String startTime;
  final String endTime;
  final String courseCode;
  final String? sectionName;
  final String? roomNumber;
  final String? faculties;
}

Map<String, List<_FriendScheduleEntry>> _groupByDay(FriendSchedule friend) {
  final grouped = <String, List<_FriendScheduleEntry>>{};
  for (final course in friend.courses) {
    for (final s in course.schedule) {
      grouped.putIfAbsent(s.day, () => []);
      grouped[s.day]!.add(
        _FriendScheduleEntry(
          day: s.day,
          startTime: s.startTime,
          endTime: s.endTime,
          courseCode: course.courseCode,
          sectionName: course.sectionName,
          roomNumber: course.roomNumber,
          faculties: course.faculties,
        ),
      );
    }
  }

  for (final entries in grouped.values) {
    entries.sort(
      (a, b) =>
          _timeToMinutes(a.startTime).compareTo(_timeToMinutes(b.startTime)),
    );
  }
  return grouped;
}

String _entryKey(_FriendScheduleEntry entry) {
  return [
    entry.day,
    entry.startTime,
    entry.endTime,
    entry.courseCode,
    entry.sectionName ?? '',
    entry.roomNumber ?? '',
    entry.faculties ?? '',
  ].join('|');
}

String? _pickNextEntryKey(FriendSchedule friend) {
  final now = DateTime.now();
  final nowMinutes = now.hour * 60 + now.minute;
  DateTime? nextDateTime;
  String? nextKey;

  for (final course in friend.courses) {
    for (final s in course.schedule) {
      final entry = _FriendScheduleEntry(
        day: s.day,
        startTime: s.startTime,
        endTime: s.endTime,
        courseCode: course.courseCode,
        sectionName: course.sectionName,
        roomNumber: course.roomNumber,
        faculties: course.faculties,
      );
      final candidate = _nextOccurrence(
        day: s.day,
        startTime: s.startTime,
        endTime: s.endTime,
        now: now,
        nowMinutes: nowMinutes,
      );
      if (candidate != null &&
          (nextDateTime == null || candidate.isBefore(nextDateTime))) {
        nextDateTime = candidate;
        nextKey = _entryKey(entry);
      }
    }
  }
  return nextKey;
}

DateTime? _nextOccurrence({
  required String day,
  required String startTime,
  required String endTime,
  required DateTime now,
  required int nowMinutes,
}) {
  final dayMap = {
    'MONDAY': DateTime.monday,
    'TUESDAY': DateTime.tuesday,
    'WEDNESDAY': DateTime.wednesday,
    'THURSDAY': DateTime.thursday,
    'FRIDAY': DateTime.friday,
    'SATURDAY': DateTime.saturday,
    'SUNDAY': DateTime.sunday,
  };
  final targetWeekday = dayMap[day.toUpperCase()];
  if (targetWeekday == null) return null;

  final startParts = startTime.split(':');
  if (startParts.length < 2) return null;
  final startHour = int.tryParse(startParts[0]) ?? 0;
  final startMinute = int.tryParse(startParts[1]) ?? 0;
  final startMinutes = startHour * 60 + startMinute;

  final endParts = endTime.split(':');
  final endHour = endParts.length >= 2 ? int.tryParse(endParts[0]) ?? 0 : 0;
  final endMinute = endParts.length >= 2 ? int.tryParse(endParts[1]) ?? 0 : 0;
  final endMinutes = endHour * 60 + endMinute;

  int daysAhead = (targetWeekday - now.weekday + 7) % 7;
  if (daysAhead == 0) {
    if (nowMinutes < endMinutes) {
      if (nowMinutes <= startMinutes) {
        return DateTime(now.year, now.month, now.day, startHour, startMinute);
      }
      return now;
    }
    daysAhead = 7;
  }
  final date = now.add(Duration(days: daysAhead));
  return DateTime(date.year, date.month, date.day, startHour, startMinute);
}

int _timeToMinutes(String time) {
  final parts = time.split(':');
  if (parts.length < 2) return 0;
  final hour = int.tryParse(parts[0]) ?? 0;
  final minute = int.tryParse(parts[1]) ?? 0;
  return hour * 60 + minute;
}

List<String> _orderedDays(List<String> days) {
  const order = [
    'SATURDAY',
    'SUNDAY',
    'MONDAY',
    'TUESDAY',
    'WEDNESDAY',
    'THURSDAY',
    'FRIDAY',
  ];
  final upper = days.map((d) => d.toUpperCase()).toSet();
  return order.where((d) => upper.contains(d)).toList();
}
