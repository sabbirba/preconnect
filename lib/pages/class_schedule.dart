import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:preconnect/api/bracu_auth_manager.dart';
import 'package:preconnect/model/section_info.dart' as section;
import 'package:preconnect/pages/shared_widgets/section_badge.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/refresh_bus.dart';
import 'package:preconnect/tools/refresh_guard.dart';

class ClassSchedule extends StatefulWidget {
  const ClassSchedule({super.key});

  static final ValueNotifier<int> jumpSignal = ValueNotifier<int>(0);

  static void requestJump() {
    jumpSignal.value++;
  }

  @override
  State<ClassSchedule> createState() => _ClassScheduleState();
}

class _ClassScheduleState extends State<ClassSchedule> {
  late Future<_ScheduleData> _future;
  final ScrollController _scrollController = ScrollController();
  GlobalKey? _highlightKey;
  String? _lastHighlightToken;
  bool _didScroll = false;
  bool _scrollRetry = false;

  @override
  void initState() {
    super.initState();
    unawaited(BracuAuthManager().fetchStudentSchedule());
    _future = _loadSchedule();
    ClassSchedule.jumpSignal.addListener(_onJumpRequested);
    RefreshBus.instance.addListener(_onRefreshSignal);
  }

  @override
  void dispose() {
    ClassSchedule.jumpSignal.removeListener(_onJumpRequested);
    _scrollController.dispose();
    RefreshBus.instance.removeListener(_onRefreshSignal);
    super.dispose();
  }

  void _onRefreshSignal() {
    if (!mounted) return;
    if (RefreshBus.instance.reason == 'class_schedule') {
      return;
    }
    unawaited(_handleRefresh(notify: false));
  }

  void _onJumpRequested() {
    _didScroll = false;
    _scrollRetry = false;
    if (mounted) {
      setState(() {});
    }
  }

  void _attemptScrollToHighlight() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _highlightKey?.currentContext;
      if (context == null) {
        if (!_scrollRetry) {
          _scrollRetry = true;
          _attemptScrollToHighlight();
        }
        return;
      }
      Scrollable.ensureVisible(
        context,
        alignment: 0.5,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
      );
      _didScroll = true;
    });
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

  Future<void> _handleRefresh({bool notify = true}) async {
    if (!await ensureOnline(context, notify: notify)) {
      return;
    }
    setState(() {
      _didScroll = false;
      _scrollRetry = false;
      _future = _loadSchedule(forceRefresh: true);
    });
    await _future;
    if (notify) {
      RefreshBus.instance.notify(reason: 'class_schedule');
    }
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
          String? highlightToken;
          _highlightKey = null;
          for (var i = 0; i < days.length; i++) {
            final day = days[i];
            final schedules = grouped[day]!;

            children.add(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  BracuSectionTitle(title: formatWeekdayTitle(day)),
                  const SizedBox(height: 10),
                  ...schedules.map((entry) {
                    final s = entry["schedule"] as section.ClassSchedule;
                    final code = entry["courseCode"];
                    final sectionName = entry["sectionName"];
                    final room = entry["roomNumber"];
                    final faculties = entry["faculties"] as String?;

                    final isHighlighted = nextSchedule == s;
                    if (isHighlighted) {
                      highlightToken =
                          '${day}_${s.startTime}_${s.endTime}_$code';
                      _highlightKey ??= GlobalKey();
                    }
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: BracuCard(
                        key: isHighlighted ? _highlightKey : null,
                        isHighlighted: isHighlighted,
                        highlightColor: BracuPalette.primary,
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SectionBadge(
                                  label: formatSectionBadge(
                                    sectionName?.toString(),
                                  ),
                                  color: BracuPalette.primary,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  flex: 7,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '$code'.trim(),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
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
                                const SizedBox(width: 12),
                                Expanded(
                                  flex: 4,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        room.toString(),
                                        textAlign: TextAlign.right,
                                        style: TextStyle(
                                          color: BracuPalette.textPrimary(
                                            context,
                                          ),
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      if (faculties != null &&
                                          faculties.trim().isNotEmpty) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          faculties,
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
                            );
                          },
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

          if (highlightToken != null && highlightToken != _lastHighlightToken) {
            _lastHighlightToken = highlightToken;
            _didScroll = false;
            _scrollRetry = false;
          }
          if (!_didScroll && _highlightKey != null) {
            _attemptScrollToHighlight();
          }

          return RefreshIndicator(
            onRefresh: _handleRefresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
              controller: _scrollController,
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
