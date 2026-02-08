import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:preconnect/api/bracu_auth_manager.dart';
import 'package:preconnect/model/section_info.dart' as section;
import 'package:preconnect/pages/ui_kit.dart';

class ClassSchedule extends StatefulWidget {
  const ClassSchedule({super.key});

  @override
  State<ClassSchedule> createState() => _ClassScheduleState();
}

class _ClassScheduleState extends State<ClassSchedule> {
  late Future<_ScheduleData> _future;

  @override
  void initState() {
    super.initState();
    unawaited(BracuAuthManager().fetchStudentSchedule());
    _future = _loadSchedule();
  }

  Future<_ScheduleData> _loadSchedule({bool forceRefresh = false}) async {
    if (forceRefresh) {
      await BracuAuthManager().fetchStudentSchedule();
    } else {
      unawaited(BracuAuthManager().fetchStudentSchedule());
    }
    final jsonString = await BracuAuthManager().getStudentSchedule();
    if (jsonString == null || jsonString.trim().isEmpty) {
      return _ScheduleData(grouped: {}, nextSchedule: null);
    }

    final decoded = jsonDecode(jsonString) as List<dynamic>;
    final sections = decoded.map((e) => section.Section.fromJson(e)).toList();

    final Map<String, List<Map<String, dynamic>>> grouped = {};
    section.ClassSchedule? nextSchedule;
    DateTime? nextDateTime;
    final now = DateTime.now();
    final nowMinutes = now.hour * 60 + now.minute;

    for (final section in sections) {
      for (final classSchedule in section.sectionSchedule.classSchedules) {
        grouped.putIfAbsent(classSchedule.day, () => []);
        grouped[classSchedule.day]!.add({
          "schedule": classSchedule,
          "courseCode": section.courseCode,
          "sectionName": section.sectionName,
          "roomNumber": section.roomNumber,
          "faculties": section.faculties,
        });

        final candidate = _nextOccurrence(
          day: classSchedule.day,
          startTime: classSchedule.startTime,
          endTime: classSchedule.endTime,
          now: now,
          nowMinutes: nowMinutes,
        );
        if (candidate != null &&
            (nextDateTime == null || candidate.isBefore(nextDateTime))) {
          nextDateTime = candidate;
          nextSchedule = classSchedule;
        }
      }
    }

    for (final entries in grouped.values) {
      entries.sort((a, b) {
        final aSchedule = a["schedule"] as section.ClassSchedule;
        final bSchedule = b["schedule"] as section.ClassSchedule;
        final aStart = _timeToMinutes(aSchedule.startTime);
        final bStart = _timeToMinutes(bSchedule.startTime);
        if (aStart != bStart) return aStart.compareTo(bStart);
        final aEnd = _timeToMinutes(aSchedule.endTime);
        final bEnd = _timeToMinutes(bSchedule.endTime);
        return aEnd.compareTo(bEnd);
      });
    }
    return _ScheduleData(grouped: grouped, nextSchedule: nextSchedule);
  }

  Future<void> _handleRefresh() async {
    setState(() {
      _future = _loadSchedule(forceRefresh: true);
    });
    await _future;
  }

  DateTime? _nextOccurrence({
    required String day,
    required String startTime,
    required String endTime,
    required DateTime now,
    required int nowMinutes,
  }) {
    final dayMap = {
      "MONDAY": DateTime.monday,
      "TUESDAY": DateTime.tuesday,
      "WEDNESDAY": DateTime.wednesday,
      "THURSDAY": DateTime.thursday,
      "FRIDAY": DateTime.friday,
      "SATURDAY": DateTime.saturday,
      "SUNDAY": DateTime.sunday,
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

  @override
  Widget build(BuildContext context) {
    return BracuPageScaffold(
      title: 'Class Schedule',
      subtitle: 'Classes & Timing',
      icon: Icons.schedule_outlined,
      body: FutureBuilder<_ScheduleData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return RefreshIndicator(
              onRefresh: _handleRefresh,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 160),
                  BracuLoading(label: 'Loading schedule...'),
                ],
              ),
            );
          }
          if (snapshot.hasError) {
            return RefreshIndicator(
              onRefresh: _handleRefresh,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  const SizedBox(height: 160),
                  BracuEmptyState(message: 'Error: ${snapshot.error}'),
                ],
              ),
            );
          }

          final grouped = snapshot.data?.grouped ?? {};
          final nextSchedule = snapshot.data?.nextSchedule;
          if (grouped.isEmpty) {
            return RefreshIndicator(
              onRefresh: _handleRefresh,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 160),
                  BracuEmptyState(message: 'No schedule data available'),
                ],
              ),
            );
          }

          final keys = grouped.keys.toList();
          List<String> days = [
            "SATURDAY",
            "SUNDAY",
            "MONDAY",
            "TUESDAY",
            "WEDNESDAY",
            "THURSDAY",
            "FRIDAY",
          ];
          days = days.where((day) => keys.contains(day)).toList();

          final children = <Widget>[];
          for (var i = 0; i < days.length; i++) {
            final day = days[i];
            final schedules = grouped[day]!;

            children.add(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  BracuSectionTitle(title: day),
                  const SizedBox(height: 10),
                  ...schedules.map((entry) {
                    final s = entry["schedule"] as section.ClassSchedule;
                    final code = entry["courseCode"];
                    final sectionName = entry["sectionName"];
                    final room = entry["roomNumber"];
                    final faculties = entry["faculties"] as String?;

                    final isHighlighted = nextSchedule == s;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: BracuCard(
                        isHighlighted: isHighlighted,
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: BracuPalette.primary.withValues(
                                  alpha: 0.12,
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                formatSectionBadge(sectionName?.toString()),
                                style: const TextStyle(
                                  color: BracuPalette.primary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '$code'.trim(),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    formatTimeRange(s.startTime, s.endTime),
                                    style: TextStyle(
                                      color: BracuPalette.textSecondary(
                                        context,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  room.toString(),
                                  style: TextStyle(
                                    color: BracuPalette.textPrimary(context),
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (faculties != null &&
                                    faculties.trim().isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    faculties,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: BracuPalette.textSecondary(
                                        context,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 6),
                ],
              ),
            );
          }
          children.add(const SizedBox(height: 8));

          return RefreshIndicator(
            onRefresh: _handleRefresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
              children: children,
            ),
          );
        },
      ),
    );
  }
}

class _ScheduleData {
  const _ScheduleData({required this.grouped, required this.nextSchedule});

  final Map<String, List<Map<String, dynamic>>> grouped;
  final section.ClassSchedule? nextSchedule;
}
