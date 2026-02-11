import 'package:flutter/material.dart';
import 'package:preconnect/model/friend_schedule.dart';
import 'package:preconnect/pages/ui_kit.dart';

class CompareSchedulesPage extends StatelessWidget {
  const CompareSchedulesPage({
    super.key,
    required this.mySchedule,
    required this.friendItem,
  });

  final List<Course>? mySchedule;
  final FriendSchedule friendItem;

  @override
  Widget build(BuildContext context) {
    if (mySchedule == null || mySchedule!.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Compare Schedules'),
        ),
        body: const Center(
          child: BracuEmptyState(
            message: 'You need to have your own schedule to compare',
          ),
        ),
      );
    }

    final comparison = CompareSchedulesPage.compareSchedules(mySchedule!, friendItem.courses);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Compare Schedules'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Header with avatars
          _buildComparisonHeader(context),
          const SizedBox(height: 24),

          // Free time slots
          if ((comparison['freeSlots'] as List?)?.isNotEmpty ?? false) ...[
            _buildSectionTitle(context, 'When You\'re Both Free', Icons.event_available),
            const SizedBox(height: 12),
            ...(comparison['freeSlots'] as List?)?.map((slot) => _buildFreeSlotCard(context, slot)) ?? [],
            const SizedBox(height: 24),
          ],

          // Common classes
          if ((comparison['commonClasses'] as List?)?.isNotEmpty ?? false) ...[
            _buildSectionTitle(context, 'Same Classes', Icons.school),
            const SizedBox(height: 12),
            ...(comparison['commonClasses'] as List?)?.map((cls) => _buildCommonClassCard(context, cls)) ?? [],
            const SizedBox(height: 24),
          ],

          // Busy times
          if ((comparison['busySlots'] as List?)?.isNotEmpty ?? false) ...[
            _buildSectionTitle(context, 'When You\'re Both Busy', Icons.event_busy),
            const SizedBox(height: 12),
            ...(comparison['busySlots'] as List?)?.map((slot) => _buildBusySlotCard(context, slot)) ?? [],
          ],
        ],
      ),
    );
  }

  Widget _buildComparisonHeader(BuildContext context) {
    return BracuCard(
      child: Row(
        children: [
          _buildAvatar('You', null),
          const SizedBox(width: 16),
          const Icon(Icons.compare_arrows, color: BracuPalette.primary, size: 32),
          const SizedBox(width: 16),
          _buildAvatar(friendItem.name, friendItem.photoUrl),
        ],
      ),
    );
  }

  Widget _buildAvatar(String name, String? photoUrl) {
    return Column(
      children: [
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: BracuPalette.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(16),
          ),
          child: photoUrl == null || photoUrl.isEmpty
              ? Center(
                  child: Text(
                    _getInitials(name),
                    style: const TextStyle(
                      color: BracuPalette.primary,
                      fontWeight: FontWeight.w700,
                      fontSize: 20,
                    ),
                  ),
                )
              : ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.network(
                    photoUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Center(
                        child: Text(
                          _getInitials(name),
                          style: const TextStyle(
                            color: BracuPalette.primary,
                            fontWeight: FontWeight.w700,
                            fontSize: 20,
                          ),
                        ),
                      );
                    },
                  ),
                ),
        ),
        const SizedBox(height: 8),
        Text(
          name,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  String _getInitials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return 'U';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts[1].substring(0, 1)).toUpperCase();
  }

  Widget _buildSectionTitle(BuildContext context, String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: BracuPalette.primary, size: 20),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: BracuPalette.textPrimary(context),
          ),
        ),
      ],
    );
  }

  Widget _buildFreeSlotCard(BuildContext context, Map<String, dynamic> slot) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: BracuCard(
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF22B573).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.event_available,
                color: Color(0xFF22B573),
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    slot['day'],
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: BracuPalette.textPrimary(context),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${slot['startTime']} - ${slot['endTime']}',
                    style: TextStyle(
                      fontSize: 12,
                      color: BracuPalette.textSecondary(context),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCommonClassCard(BuildContext context, String courseCode) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: BracuCard(
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: BracuPalette.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.school,
                color: BracuPalette.primary,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              courseCode,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: BracuPalette.textPrimary(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBusySlotCard(BuildContext context, Map<String, dynamic> slot) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: BracuCard(
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFEF6C35).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.event_busy,
                color: Color(0xFFEF6C35),
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    slot['day'],
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: BracuPalette.textPrimary(context),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${slot['startTime']} - ${slot['endTime']}',
                    style: TextStyle(
                      fontSize: 12,
                      color: BracuPalette.textSecondary(context),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Map<String, List> compareSchedules(
    List<Course> myCourses,
    List<Course> friendCourses,
  ) {
    print('=== COMPARE SCHEDULES DEBUG ===');
    print('My courses count: ${myCourses.length}');
    print('Friend courses count: ${friendCourses.length}');
    
    final freeSlots = <Map<String, dynamic>>[];
    final busySlots = <Map<String, dynamic>>[];
    final commonClasses = <String>{};

    // Find common classes
    for (final myCourse in myCourses) {
      print('My course: ${myCourse.courseCode}, schedules: ${myCourse.schedule.length}');
      for (final friendCourse in friendCourses) {
        if (myCourse.courseCode == friendCourse.courseCode) {
          commonClasses.add(myCourse.courseCode);
          print('Found common class: ${myCourse.courseCode}');
        }
      }
    }

    // Build schedule maps by day and time
    final myScheduleMap = _buildScheduleMap(myCourses);
    final friendScheduleMap = _buildScheduleMap(friendCourses);
    
    print('My schedule map days: ${myScheduleMap.keys}');
    print('Friend schedule map days: ${friendScheduleMap.keys}');

    final days = ['Saturday', 'Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday'];

    for (final day in days) {
      final mySlots = myScheduleMap[day] ?? [];
      final friendSlots = friendScheduleMap[day] ?? [];

      print('$day - My slots: ${mySlots.length}, Friend slots: ${friendSlots.length}');

      if (mySlots.isEmpty || friendSlots.isEmpty) continue;

      // Find overlapping busy times
      for (final mySlot in mySlots) {
        for (final friendSlot in friendSlots) {
          final myStart = mySlot['startTime'] as String?;
          final myEnd = mySlot['endTime'] as String?;
          final friendStart = friendSlot['startTime'] as String?;
          final friendEnd = friendSlot['endTime'] as String?;
          
          if (myStart != null && myEnd != null && friendStart != null && friendEnd != null &&
              _timesOverlap(myStart, myEnd, friendStart, friendEnd)) {
            busySlots.add({
              'day': day,
              'startTime': _laterTime(myStart, friendStart),
              'endTime': _earlierTime(myEnd, friendEnd),
            });
          }
        }
      }

      // Find free slots (simplified - assumes 8 AM to 8 PM)
      final allSlots = [...mySlots, ...friendSlots];
      allSlots.sort((a, b) => _compareTime(a['startTime'] as String, b['startTime'] as String));

      String currentTime = '08:00 AM';
      const endOfDay = '08:00 PM';

      for (final slot in allSlots) {
        final slotStart = slot['startTime'] as String?;
        final slotEnd = slot['endTime'] as String?;
        
        if (slotStart != null && _compareTime(currentTime, slotStart) < 0) {
          freeSlots.add({
            'day': day,
            'startTime': currentTime,
            'endTime': slotStart,
          });
        }
        if (slotEnd != null) {
          currentTime = _laterTime(currentTime, slotEnd);
        }
      }

      if (_compareTime(currentTime, endOfDay) < 0) {
        freeSlots.add({
          'day': day,
          'startTime': currentTime,
          'endTime': endOfDay,
        });
      }
    }

    print('Free slots found: ${freeSlots.length}');
    print('Busy slots found: ${busySlots.length}');
    print('Common classes found: ${commonClasses.length}');

    return {
      'freeSlots': freeSlots,
      'busySlots': busySlots,
      'commonClasses': commonClasses.toList(),
    };
  }

  static Map<String, List<Map<String, String>>> _buildScheduleMap(List<Course> courses) {
    final map = <String, List<Map<String, String>>>{};

    for (final course in courses) {
      for (final schedule in course.schedule) {
        map.putIfAbsent(schedule.day, () => []).add({
          'startTime': schedule.startTime,
          'endTime': schedule.endTime,
        });
      }
    }

    return map;
  }

  static bool _timesOverlap(String start1, String end1, String start2, String end2) {
    return _compareTime(start1, end2) < 0 && _compareTime(start2, end1) < 0;
  }

  static String _laterTime(String time1, String time2) {
    return _compareTime(time1, time2) > 0 ? time1 : time2;
  }

  static String _earlierTime(String time1, String time2) {
    return _compareTime(time1, time2) < 0 ? time1 : time2;
  }

  static int _compareTime(String time1, String time2) {
    final t1 = _parseTime(time1);
    final t2 = _parseTime(time2);
    return t1.compareTo(t2);
  }

  static int _parseTime(String time) {
    final parts = time.trim().split(' ');
    final timeParts = parts[0].split(':');
    var hour = int.parse(timeParts[0]);
    final minute = int.parse(timeParts[1]);
    final isPM = parts.length > 1 && parts[1].toUpperCase() == 'PM';

    if (isPM && hour != 12) hour += 12;
    if (!isPM && hour == 12) hour = 0;

    return hour * 60 + minute;
  }
}
