import 'package:flutter/material.dart';
import 'package:preconnect/model/friend_schedule.dart';
import 'package:preconnect/pages/friend_schedule_sections/friend_header.dart';
import 'package:preconnect/pages/ui_kit.dart';

class FriendScheduleItem {
  const FriendScheduleItem({
    required this.encoded,
    required this.friend,
    this.metadata,
  });

  final String encoded;
  final FriendSchedule friend;
  final FriendMetadata? metadata;

  String get displayName =>
      metadata?.nickname?.trim().isNotEmpty == true
          ? metadata!.nickname!
          : friend.name;

  bool get isFavorite => metadata?.isFavorite ?? false;
}

class FriendScheduleSection extends StatelessWidget {
  const FriendScheduleSection({
    super.key,
    required this.item,
    required this.onDelete,
    this.onToggleFavorite,
    this.onEditNickname,
    this.onTap,
  });

  final FriendScheduleItem item;
  final VoidCallback onDelete;
  final VoidCallback? onToggleFavorite;
  final VoidCallback? onEditNickname;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final friend = item.friend;
    final courseCount = friend.courses.length;
    final nextClass = _pickNextClassSummary(friend);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: FriendHeaderCard(
        friend: friend,
        onDelete: onDelete,
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

/// Returns a short summary of the friend's next upcoming class, e.g. "Next: CSE110 Sun 8:00 AM".
String? _pickNextClassSummary(FriendSchedule friend) {
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
      final targetWeekday = dayMap[s.day.toUpperCase()];
      if (targetWeekday == null) continue;

      int daysAhead = (targetWeekday - now.weekday + 7) % 7;

      // Parse start time for comparison
      final timeParts = s.startTime.split(RegExp(r'[:\s]+'));
      int h = int.tryParse(timeParts.isNotEmpty ? timeParts[0] : '') ?? 0;
      final m = int.tryParse(timeParts.length > 1 ? timeParts[1] : '') ?? 0;
      final isPm = s.startTime.toUpperCase().contains('PM') && h != 12;
      final isAm12 = s.startTime.toUpperCase().contains('AM') && h == 12;
      if (isPm) h += 12;
      if (isAm12) h = 0;
      final startMinutes = h * 60 + m;

      if (daysAhead == 0 && nowMinutes >= startMinutes) {
        daysAhead = 7;
      }

      final candidate = DateTime(now.year, now.month, now.day, h, m)
          .add(Duration(days: daysAhead));

      if (best == null || candidate.isBefore(best)) {
        best = candidate;
        final shortDay = s.day.length > 3 ? s.day.substring(0, 3) : s.day;
        bestLabel = 'Next: ${course.courseCode} $shortDay ${s.startTime}';
      }
    }
  }
  return bestLabel;
}
