import 'package:flutter/material.dart';
import 'package:preconnect/model/friend_schedule.dart';
import 'package:preconnect/pages/friend_schedule_sections/friend_header.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/ramadan.dart';
import 'package:preconnect/tools/time_utils.dart';

class FriendScheduleItem {
  const FriendScheduleItem({
    required this.encoded,
    required this.friend,
    this.metadata,
  });

  final String encoded;
  final FriendSchedule friend;
  final FriendMetadata? metadata;

  String get displayName => metadata?.nickname?.trim().isNotEmpty == true
      ? metadata!.nickname!
      : friend.name;

  bool get isFavorite => metadata?.isFavorite ?? false;
}

class FriendScheduleSection extends StatelessWidget {
  const FriendScheduleSection({
    super.key,
    required this.item,
    this.isRamadan = false,
    this.onDelete,
    this.onToggleFavorite,
    this.onEditNickname,
    this.onTap,
    this.showActions = true,
  });

  final FriendScheduleItem item;
  final bool isRamadan;
  final VoidCallback? onDelete;
  final VoidCallback? onToggleFavorite;
  final VoidCallback? onEditNickname;
  final VoidCallback? onTap;
  final bool showActions;

  @override
  Widget build(BuildContext context) {
    final friend = item.friend;
    final courseCount = friend.courses.length;
    final nextClass = _pickNextClassSummary(friend, isRamadan: isRamadan);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: FriendHeaderCard(
        friend: friend,
        onDelete: onDelete,
        showActions: showActions,
        displayName: item.displayName,
        isFavorite: item.isFavorite,
        onToggleFavorite: onToggleFavorite,
        onEditNickname: onEditNickname,
        onTap: onTap,
        subtitle: courseCount == 0
            ? 'No schedule shared'
            : '$courseCount course${courseCount == 1 ? '' : 's'}${nextClass != null ? ' · $nextClass' : ''}',
      ),
    );
  }
}

(int hour, int minute)? _parse24h(String raw) {
  return BracuTime.parseHourMinute(raw);
}

String? _pickNextClassSummary(
  FriendSchedule friend, {
  required bool isRamadan,
}) {
  if (friend.courses.isEmpty) return null;

  final dayMap = {
    'SATURDAY': DateTime.saturday,
    'SUNDAY': DateTime.sunday,
    'MONDAY': DateTime.monday,
    'TUESDAY': DateTime.tuesday,
    'WEDNESDAY': DateTime.wednesday,
    'THURSDAY': DateTime.thursday,
    'FRIDAY': DateTime.friday,
  };

  final now = DateTime.now();
  final nowMinutes = now.hour * 60 + now.minute;
  DateTime? best;
  String? bestLabel;

  for (final course in friend.courses) {
    for (final s in course.schedule) {
      final adjusted = RamadanTiming.adjustRange(
        s.startTime,
        s.endTime,
        isRamadan: isRamadan,
      );
      final normalizedDay = normalizeWeekday(s.day);
      final targetWeekday = dayMap[normalizedDay];
      if (targetWeekday == null) continue;

      int daysAhead = (targetWeekday - now.weekday + 7) % 7;

      final parsed = _parse24h(adjusted.startTime);
      if (parsed == null) continue;
      final (h, m) = parsed;
      final startMinutes = h * 60 + m;

      if (daysAhead == 0 && nowMinutes >= startMinutes) {
        daysAhead = 7;
      }

      final candidate = DateTime(
        now.year,
        now.month,
        now.day,
        h,
        m,
      ).add(Duration(days: daysAhead));

      if (best == null || candidate.isBefore(best)) {
        best = candidate;
        final shortDay = formatWeekdayTitle(s.day);
        final displayDay = shortDay.length > 3
            ? shortDay.substring(0, 3)
            : shortDay;
        final displayTime = formatTime(adjusted.startTime);
        bestLabel = 'Next: ${course.courseCode} $displayDay $displayTime';
      }
    }
  }
  return bestLabel;
}
