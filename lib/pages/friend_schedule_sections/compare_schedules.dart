import 'dart:async';
import 'package:flutter/material.dart';
import 'package:preconnect/model/friend_schedule.dart';
import 'package:preconnect/pages/friend_schedule_sections/friend_header.dart';
import 'package:preconnect/pages/shared_widgets/section_badge.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CompareSchedulesPage extends StatefulWidget {
  const CompareSchedulesPage({
    super.key,
    required this.mySchedule,
    required this.friendItem,
    this.myPhotoUrl,
  });

  final List<Course>? mySchedule;
  final FriendSchedule friendItem;
  final String? myPhotoUrl;

  @override
  State<CompareSchedulesPage> createState() => _CompareSchedulesPageState();

  static Map<String, List> compareSchedules(
    List<Course> myCourses,
    List<Course> friendCourses,
  ) {
    final freeSlots = <Map<String, dynamic>>[];
    final busySlots = <Map<String, dynamic>>[];
    final commonClasses = <String>{};

    final myCodes = myCourses
        .map((c) => c.courseCode.trim())
        .where((c) => c.isNotEmpty)
        .toSet();
    final friendCodes = friendCourses
        .map((c) => c.courseCode.trim())
        .where((c) => c.isNotEmpty)
        .toSet();
    for (final code in myCodes) {
      if (friendCodes.contains(code)) commonClasses.add(code);
    }

    final myScheduleMap = _buildScheduleMap(myCourses);
    final friendScheduleMap = _buildScheduleMap(friendCourses);

    const days = [
      'Saturday',
      'Sunday',
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
    ];

    for (final day in days) {
      final mySlots = myScheduleMap[day] ?? [];
      final friendSlots = friendScheduleMap[day] ?? [];
      final mergedMy = _mergeSlots(mySlots);
      final mergedFriend = _mergeSlots(friendSlots);

      final overlaps = _intersectSlots(mergedMy, mergedFriend);
      for (final slot in overlaps) {
        busySlots.add({
          'day': day,
          'startTime': slot['startTime'],
          'endTime': slot['endTime'],
        });
      }

      final myFree = _freeWithinDay(mergedMy);
      final friendFree = _freeWithinDay(mergedFriend);
      final sharedFree = _intersectSlots(myFree, friendFree);
      for (final slot in sharedFree) {
        freeSlots.add({
          'day': day,
          'startTime': slot['startTime'],
          'endTime': slot['endTime'],
        });
      }
    }

    return {
      'freeSlots': freeSlots,
      'busySlots': busySlots,
      'commonClasses': commonClasses.toList(),
    };
  }

  static Map<String, List<Map<String, String>>> _buildScheduleMap(
    List<Course> courses,
  ) {
    final map = <String, List<Map<String, String>>>{};

    for (final course in courses) {
      for (final schedule in course.schedule) {
        final day = _normalizeDay(schedule.day);
        if (day.isEmpty) continue;
        map.putIfAbsent(day, () => []).add({
          'startTime': schedule.startTime,
          'endTime': schedule.endTime,
        });
      }
    }

    return map;
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

  static String _normalizeDay(String raw) {
    final day = raw.trim().toLowerCase();
    if (day.isEmpty) return '';
    return day[0].toUpperCase() + day.substring(1);
  }

  static List<Map<String, String>> _mergeSlots(
    List<Map<String, String>> slots,
  ) {
    if (slots.isEmpty) return const [];
    final sorted = [...slots];
    sorted.sort((a, b) => _compareTime(a['startTime']!, b['startTime']!));
    final merged = <Map<String, String>>[];

    for (final slot in sorted) {
      final start = slot['startTime'];
      final end = slot['endTime'];
      if (start == null || end == null) continue;
      if (merged.isEmpty) {
        merged.add({'startTime': start, 'endTime': end});
        continue;
      }
      final last = merged.last;
      final lastEnd = last['endTime']!;
      if (_compareTime(start, lastEnd) <= 0) {
        if (_compareTime(end, lastEnd) > 0) {
          last['endTime'] = end;
        }
      } else {
        merged.add({'startTime': start, 'endTime': end});
      }
    }
    return merged;
  }

  static List<Map<String, String>> _intersectSlots(
    List<Map<String, String>> a,
    List<Map<String, String>> b,
  ) {
    final result = <Map<String, String>>[];
    var i = 0;
    var j = 0;
    while (i < a.length && j < b.length) {
      final aStart = a[i]['startTime']!;
      final aEnd = a[i]['endTime']!;
      final bStart = b[j]['startTime']!;
      final bEnd = b[j]['endTime']!;
      final start = _laterTime(aStart, bStart);
      final end = _earlierTime(aEnd, bEnd);
      if (_compareTime(start, end) < 0) {
        result.add({'startTime': start, 'endTime': end});
      }
      if (_compareTime(aEnd, bEnd) <= 0) {
        i++;
      } else {
        j++;
      }
    }
    return result;
  }

  static List<Map<String, String>> _freeWithinDay(
    List<Map<String, String>> busy,
  ) {
    const dayStart = '08:00 AM';
    const dayEnd = '08:00 PM';
    if (busy.isEmpty) {
      return const [
        {'startTime': dayStart, 'endTime': dayEnd},
      ];
    }
    final free = <Map<String, String>>[];
    var current = dayStart;
    for (final slot in busy) {
      final start = slot['startTime']!;
      final end = slot['endTime']!;
      if (_compareTime(current, start) < 0) {
        free.add({'startTime': current, 'endTime': start});
      }
      if (_compareTime(end, current) > 0) current = end;
    }
    if (_compareTime(current, dayEnd) < 0) {
      free.add({'startTime': current, 'endTime': dayEnd});
    }
    return free;
  }
}

class _CompareSchedulesPageState extends State<CompareSchedulesPage> {
  final Set<String> _pinnedEntries = <String>{};

  @override
  void initState() {
    super.initState();
    unawaited(_loadPins());
  }

  String _pinKey() {
    final friendId = widget.friendItem.id.trim().isEmpty
        ? 'unknown'
        : widget.friendItem.id.trim();
    return 'compare_pins_${friendId}_all';
  }

  Future<void> _loadPins() async {
    final prefs = await SharedPreferences.getInstance();
    final all = prefs.getStringList(_pinKey()) ?? const <String>[];
    if (!mounted) return;
    setState(() {
      _pinnedEntries
        ..clear()
        ..addAll(all);
    });
  }

  Future<void> _savePins() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_pinKey(), _pinnedEntries.toList());
  }

  void _togglePin(String key) {
    setState(() {
      if (_pinnedEntries.contains(key)) {
        _pinnedEntries.remove(key);
      } else {
        _pinnedEntries.add(key);
      }
    });
    unawaited(_savePins());
  }

  List<_DayCompareEntry> _buildEntries(
    List<Map<String, dynamic>> freeSlots,
    List<Map<String, dynamic>> busySlots,
    List<String> commonClasses,
  ) {
    final entries = <_DayCompareEntry>[];

    for (final slot in freeSlots) {
      final day = (slot['day'] ?? '').toString();
      final start = (slot['startTime'] ?? '').toString();
      final end = (slot['endTime'] ?? '').toString();
      entries.add(
        _DayCompareEntry(
          day: day,
          type: _CompareType.free,
          title: 'Free',
          subtitle: '$start - $end',
          key: 'free|$day|$start|$end',
        ),
      );
    }

    for (final slot in busySlots) {
      final day = (slot['day'] ?? '').toString();
      final start = (slot['startTime'] ?? '').toString();
      final end = (slot['endTime'] ?? '').toString();
      entries.add(
        _DayCompareEntry(
          day: day,
          type: _CompareType.busy,
          title: 'Busy',
          subtitle: '$start - $end',
          key: 'busy|$day|$start|$end',
        ),
      );
    }

    final myCourses = widget.mySchedule ?? const <Course>[];
    for (final code in commonClasses) {
      final days = _commonDaysForCode(
        code,
        myCourses,
        widget.friendItem.courses,
      );
      if (days.isEmpty) {
        entries.add(
          _DayCompareEntry(
            day: 'General',
            type: _CompareType.common,
            title: code,
            subtitle: 'Common class',
            key: 'common|general|$code',
          ),
        );
      } else {
        for (final day in days) {
          entries.add(
            _DayCompareEntry(
              day: day,
              type: _CompareType.common,
              title: code,
              subtitle: 'Common class',
              key: 'common|$day|$code',
            ),
          );
        }
      }
    }

    return entries;
  }

  Set<String> _commonDaysForCode(
    String courseCode,
    List<Course> myCourses,
    List<Course> friendCourses,
  ) {
    final myDays = <String>{};
    final friendDays = <String>{};

    for (final c in myCourses) {
      if (c.courseCode.trim() != courseCode.trim()) continue;
      for (final s in c.schedule) {
        final day = CompareSchedulesPage._normalizeDay(s.day);
        if (day.isNotEmpty) myDays.add(day);
      }
    }

    for (final c in friendCourses) {
      if (c.courseCode.trim() != courseCode.trim()) continue;
      for (final s in c.schedule) {
        final day = CompareSchedulesPage._normalizeDay(s.day);
        if (day.isNotEmpty) friendDays.add(day);
      }
    }

    final intersection = myDays.where(friendDays.contains).toSet();
    if (intersection.isNotEmpty) return intersection;
    return {...myDays, ...friendDays};
  }

  Map<String, List<_DayCompareEntry>> _groupByDay(List<_DayCompareEntry> all) {
    final grouped = <String, List<_DayCompareEntry>>{};
    for (final e in all) {
      grouped.putIfAbsent(e.day, () => []).add(e);
    }

    for (final day in grouped.keys.toList()) {
      final list = grouped[day]!;
      list.sort((a, b) {
        final ap = _pinnedEntries.contains(a.key) ? 0 : 1;
        final bp = _pinnedEntries.contains(b.key) ? 0 : 1;
        if (ap != bp) return ap.compareTo(bp);
        return a.subtitle.compareTo(b.subtitle);
      });
    }

    final ordered = <String, List<_DayCompareEntry>>{};
    const dayOrder = [
      'Saturday',
      'Sunday',
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'General',
    ];
    for (final day in dayOrder) {
      final list = grouped[day];
      if (list == null || list.isEmpty) continue;
      ordered[day] = list;
    }
    for (final entry in grouped.entries) {
      if (ordered.containsKey(entry.key)) continue;
      ordered[entry.key] = entry.value;
    }
    return ordered;
  }

  @override
  Widget build(BuildContext context) {
    final title = 'Compare Schedules';
    final subtitle =
        'With ${widget.friendItem.name.trim().isEmpty ? 'Friend' : widget.friendItem.name}';

    if (widget.mySchedule == null || widget.mySchedule!.isEmpty) {
      return Scaffold(
        body: BracuPageScaffold(
          title: title,
          subtitle: subtitle,
          icon: Icons.compare_arrows_rounded,
          body: const Center(
            child: BracuEmptyState(
              message: 'You need to have your own schedule to compare',
            ),
          ),
        ),
      );
    }

    final comparison = CompareSchedulesPage.compareSchedules(
      widget.mySchedule!,
      widget.friendItem.courses,
    );
    final freeSlots =
        (comparison['freeSlots'] ?? const <Map<String, dynamic>>[])
            .cast<Map<String, dynamic>>();
    final busySlots =
        (comparison['busySlots'] ?? const <Map<String, dynamic>>[])
            .cast<Map<String, dynamic>>();
    final commonClasses = (comparison['commonClasses'] ?? const <dynamic>[])
        .cast<String>();

    final entries = _buildEntries(freeSlots, busySlots, commonClasses);
    final grouped = _groupByDay(entries);

    return Scaffold(
      body: BracuPageScaffold(
        title: title,
        subtitle: subtitle,
        icon: Icons.compare_arrows_rounded,
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _buildPeopleCard(context),
            const SizedBox(height: 12),
            if (entries.isEmpty)
              const BracuCard(
                child: Text('No overlap found in available schedule data.'),
              )
            else
              ...grouped.entries.expand((entry) sync* {
                yield Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: BracuSectionTitle(title: entry.key),
                );
                for (final item in entry.value) {
                  final pinned = _pinnedEntries.contains(item.key);
                  yield _buildEntryCard(context, item, pinned);
                }
                yield const SizedBox(height: 8);
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildPeopleCard(BuildContext context) {
    final textPrimary = BracuPalette.textPrimary(context);
    final textSecondary = BracuPalette.textSecondary(context);
    return BracuCard(
      child: Row(
        children: [
          _buildPerson(
            label: 'You',
            scheduleCount: widget.mySchedule?.length ?? 0,
            photoUrl: widget.myPhotoUrl,
            textPrimary: textPrimary,
            textSecondary: textSecondary,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Icon(
              Icons.compare_arrows_rounded,
              color: BracuPalette.primary.withValues(alpha: 0.7),
              size: 24,
            ),
          ),
          _buildPerson(
            label: 'Friend',
            scheduleCount: widget.friendItem.courses.length,
            photoUrl: widget.friendItem.photoUrl,
            textPrimary: textPrimary,
            textSecondary: textSecondary,
          ),
        ],
      ),
    );
  }

  Widget _buildPerson({
    required String label,
    required int scheduleCount,
    required String? photoUrl,
    required Color textPrimary,
    required Color textSecondary,
  }) {
    final scheduleWord = scheduleCount == 1 ? 'Schedule' : 'Schedules';
    return Expanded(
      child: Row(
        children: [
          FriendAvatar(name: label, photoUrl: photoUrl),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$scheduleCount $scheduleWord',
                  style: TextStyle(fontSize: 11, color: textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEntryCard(
    BuildContext context,
    _DayCompareEntry item,
    bool isPinned,
  ) {
    final (badgeLabel, color) = switch (item.type) {
      _CompareType.free => ('FR', BracuPalette.accent),
      _CompareType.busy => ('BZ', BracuPalette.warning),
      _CompareType.common => ('CM', BracuPalette.primary),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: BracuCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionBadge(label: badgeLabel, color: color),
            const SizedBox(width: 12),
            Expanded(
              flex: 7,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: BracuPalette.textPrimary(context),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: BracuPalette.textSecondary(context),
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: isPinned ? 'Unpin' : 'Pin to top',
              onPressed: () => _togglePin(item.key),
              icon: Icon(
                isPinned ? Icons.star_rounded : Icons.star_outline_rounded,
                color: isPinned ? BracuPalette.favorite : color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _CompareType { free, busy, common }

class _DayCompareEntry {
  const _DayCompareEntry({
    required this.day,
    required this.type,
    required this.title,
    required this.subtitle,
    required this.key,
  });

  final String day;
  final _CompareType type;
  final String title;
  final String subtitle;
  final String key;
}
