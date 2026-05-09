import 'dart:async';
import 'package:flutter/material.dart';
import 'package:preconnect/api/schedule_service.dart';
import 'package:preconnect/model/section_info.dart' as section;
import 'package:preconnect/pages/shared_widgets/course_community_sheet.dart';
import 'package:preconnect/pages/shared_widgets/schedule_entry_card.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/async_preload_cache.dart';
import 'package:preconnect/tools/refresh_bus.dart';
import 'package:preconnect/tools/ramadan_timing.dart';
import 'package:preconnect/tools/time_utils.dart';

class ClassSchedule extends StatefulWidget {
  const ClassSchedule({super.key});

  static final ValueNotifier<int> jumpSignal = ValueNotifier<int>(0);

  static Future<void> preload() async {
    await _ClassScheduleState.preloadData();
  }

  static void requestJump() {
    jumpSignal.value++;
  }

  @override
  State<ClassSchedule> createState() => _ClassScheduleState();
}

class _ClassScheduleState extends State<ClassSchedule> with RefreshBusState {
  static const int _initialVisibleWeekCount = 1;
  static const List<String> _weekdayNames = <String>[
    'MONDAY',
    'TUESDAY',
    'WEDNESDAY',
    'THURSDAY',
    'FRIDAY',
    'SATURDAY',
    'SUNDAY',
  ];

  static final AsyncPreloadCache<_ScheduleData> _preloadCache =
      AsyncPreloadCache<_ScheduleData>();

  late Future<_ScheduleData> _future;
  _ScheduleData? _latestData;
  final ScrollController _scrollController = ScrollController();
  final BracuHighlightScroller _highlightScroller = BracuHighlightScroller();
  int _visibleWeekCount = _initialVisibleWeekCount;

  @override
  void initState() {
    super.initState();
    _latestData = _preloadCache.value;
    _future = preloadData();
    ClassSchedule.jumpSignal.addListener(_onJumpRequested);
    bindRefreshBus(_onRefreshSignal);
  }

  static Future<_ScheduleData> preloadData({bool forceRefresh = false}) async {
    return _preloadCache.get(
      forceRefresh: forceRefresh,
      loader: () => _loadScheduleData(forceRefresh: forceRefresh),
    );
  }

  static Future<_ScheduleData> _loadScheduleData({
    bool forceRefresh = false,
  }) async {
    final scheduleService = ScheduleService();
    final ramadanFuture = RamadanTiming.isRamadan(forceRefresh: forceRefresh);
    final sections = await scheduleService.getCurrentSemesterSections(
      forceRefresh: forceRefresh,
    );
    final isRamadan = await ramadanFuture;
    return _buildScheduleDataFromSectionsStatic(
      sections,
      shouldHighlightCurrentSemester: true,
      isRamadan: isRamadan,
    );
  }

  @override
  void dispose() {
    ClassSchedule.jumpSignal.removeListener(_onJumpRequested);
    _scrollController.dispose();
    unbindRefreshBus(_onRefreshSignal);
    super.dispose();
  }

  void _onRefreshSignal() {
    if (!mounted) return;
    if (isRefreshingFrom('class_schedule')) {
      return;
    }
    if (isRefreshingFrom('cache_cleared')) {
      unawaited(_handleRefresh(notify: false));
      return;
    }
    unawaited(_handleRefresh(notify: false));
  }

  void _onJumpRequested() {
    _highlightScroller.reset();
    if (mounted) {
      setState(() {
        _visibleWeekCount = _initialVisibleWeekCount;
      });
    }
  }

  void _attemptScrollToHighlight() {
    _highlightScroller.attempt(
      mounted: mounted,
      rebuild: _attemptScrollToHighlight,
    );
  }

  static _ScheduleData _buildScheduleDataFromSectionsStatic(
    List<section.Section> sections, {
    required bool shouldHighlightCurrentSemester,
    required bool isRamadan,
  }) {
    if (sections.isEmpty) {
      return _ScheduleData(
        grouped: {},
        scrollSchedule: null,
        scrollDateTime: null,
        isRamadan: isRamadan,
      );
    }

    final Map<String, List<Map<String, dynamic>>> grouped = {};
    section.ClassSchedule? scrollSchedule;
    DateTime? scrollDateTime;
    final now = DateTime.now();
    final nowMinutes = now.hour * 60 + now.minute;

    for (final section in sections) {
      for (final classSchedule in section.sectionSchedule.classSchedules) {
        grouped.putIfAbsent(classSchedule.day, () => []);
        grouped[classSchedule.day]!.add({
          'schedule': classSchedule,
          'courseCode': section.courseCode,
          'sectionName': section.sectionName,
          'roomNumber': section.roomNumber,
          'faculties': section.faculties,
          'consumedSeat': section.consumedSeat,
          'capacity': section.capacity,
          'courseType': section.courseType,
          'semesterSessionId': section.semesterSessionId,
        });

        if (shouldHighlightCurrentSemester) {
          final candidate = _nextOccurrenceStatic(
            day: classSchedule.day,
            startTime: classSchedule.startTime,
            endTime: classSchedule.endTime,
            isRamadan: isRamadan,
            now: now,
            nowMinutes: nowMinutes,
          );
          if (candidate != null &&
              (scrollDateTime == null || candidate.isBefore(scrollDateTime))) {
            scrollDateTime = candidate;
            scrollSchedule = classSchedule;
          }
        }
      }
    }

    for (final entries in grouped.values) {
      entries.sort((a, b) {
        final aSchedule = a['schedule'] as section.ClassSchedule;
        final bSchedule = b['schedule'] as section.ClassSchedule;
        final aStart = RamadanTiming.effectiveStartMinutes(
          aSchedule.startTime,
          aSchedule.endTime,
          isRamadan: isRamadan,
        );
        final bStart = RamadanTiming.effectiveStartMinutes(
          bSchedule.startTime,
          bSchedule.endTime,
          isRamadan: isRamadan,
        );
        if (aStart != bStart) return aStart.compareTo(bStart);
        final aEnd = RamadanTiming.effectiveEndMinutes(
          aSchedule.startTime,
          aSchedule.endTime,
          isRamadan: isRamadan,
        );
        final bEnd = RamadanTiming.effectiveEndMinutes(
          bSchedule.startTime,
          bSchedule.endTime,
          isRamadan: isRamadan,
        );
        return aEnd.compareTo(bEnd);
      });
    }

    return _ScheduleData(
      grouped: grouped,
      scrollSchedule: scrollSchedule,
      scrollDateTime: scrollDateTime,
      isRamadan: isRamadan,
    );
  }

  static DateTime? _nextOccurrenceStatic({
    required String day,
    required String startTime,
    required String endTime,
    required bool isRamadan,
    required DateTime now,
    required int nowMinutes,
  }) {
    final targetWeekday = BracuTime.weekdayFromName(day);
    if (targetWeekday == null) return null;

    final adjusted = RamadanTiming.adjustRange(
      startTime,
      endTime,
      isRamadan: isRamadan,
    );

    final startParsed = BracuTime.parseHourMinute(adjusted.startTime);
    if (startParsed == null) return null;
    final (startHour, startMinute) = startParsed;
    final startMinutes = startHour * 60 + startMinute;

    final endParsed = BracuTime.parseHourMinute(adjusted.endTime);
    final endHour = endParsed?.$1 ?? 0;
    final endMinute = endParsed?.$2 ?? 0;
    final endMinutes = endHour * 60 + endMinute;

    if (targetWeekday != now.weekday || nowMinutes >= endMinutes) {
      return null;
    }
    if (nowMinutes <= startMinutes) {
      return DateTime(now.year, now.month, now.day, startHour, startMinute);
    }
    return now;
  }

  Future<void> _handleRefresh({bool notify = true}) async {
    if (!await ensureOnline(context, notify: notify)) {
      return;
    }
    Future<_ScheduleData> refreshedFuture;
    try {
      refreshedFuture = preloadData(forceRefresh: true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _future = Future<_ScheduleData>.error(error);
        });
      }
      rethrow;
    }
    setState(() {
      _highlightScroller.reset();
      _visibleWeekCount = _initialVisibleWeekCount;
      _future = refreshedFuture;
    });
    final refreshed = await refreshedFuture;
    if (!mounted) return;
    setState(() {
      _latestData = refreshed;
    });
    if (notify) {
      RefreshBus.instance.notify(reason: 'class_schedule');
    }
  }

  Future<void> _openClassActionsSheet({
    required String courseCode,
    required String sectionName,
    required section.ClassSchedule schedule,
    required bool isRamadan,
    required String? roomNumber,
    required String? faculties,
    required int? consumedSeat,
    required String? courseType,
    required String semesterLabel,
  }) async {
    await showBracuBottomSheet<void>(
      context,
      title: courseCode,
      initialChildSize: 0.88,
      builder: (sheetContext, textPrimary, textSecondary) {
        return CourseCommunitySheet.forClass(
          courseCode: courseCode,
          sectionName: sectionName,
          classSchedule: schedule,
          isRamadan: isRamadan,
          roomNumber: roomNumber,
          faculties: faculties,
          consumedSeat: consumedSeat,
          courseType: courseType,
          semesterLabel: semesterLabel,
        );
      },
    );
  }

  List<_RenderedScheduleSection> _buildRenderedSections(
    Map<String, List<Map<String, dynamic>>> grouped, {
    required bool shouldHighlightCurrentSemester,
  }) {
    if (!shouldHighlightCurrentSemester) {
      return _weekdayNames
          .where(grouped.containsKey)
          .map(
            (day) =>
                _RenderedScheduleSection(day: day, date: null, weekOffset: 0),
          )
          .toList();
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final totalDays = _visibleWeekCount * 7;
    final sections = <_RenderedScheduleSection>[];

    for (var dayOffset = 0; dayOffset < totalDays; dayOffset++) {
      final date = today.add(Duration(days: dayOffset));
      final day = _weekdayNames[date.weekday - 1];
      if (!grouped.containsKey(day)) continue;
      sections.add(
        _RenderedScheduleSection(
          day: day,
          date: date,
          weekOffset: dayOffset ~/ 7,
        ),
      );
    }

    return sections;
  }

  @override
  Widget build(BuildContext context) {
    return BracuPageScaffold(
      title: 'Schedules',
      subtitle: 'Class Timing',
      icon: Icons.schedule_outlined,
      actions: const [],
      body: FutureBuilder<_ScheduleData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError && _latestData == null) {
            return buildRefreshErrorState(
              onRefresh: _handleRefresh,
              error: snapshot.error,
            );
          }

          final data = _latestData ?? snapshot.data;
          if (data == null) {
            return buildRefreshLoadingState(onRefresh: _handleRefresh);
          }
          final grouped = data.grouped;
          final scrollSchedule = data.scrollSchedule;
          final scrollDateTime = data.scrollDateTime;
          const shouldHighlightCurrentSemester = true;
          final isRamadan = data.isRamadan;
          if (grouped.isEmpty) {
            return buildRefreshEmptyState(
              onRefresh: _handleRefresh,
              message: 'No schedule data available',
            );
          }

          final sections = _buildRenderedSections(
            grouped,
            shouldHighlightCurrentSemester: shouldHighlightCurrentSemester,
          );

          final children = <Widget>[];
          String? highlightToken;
          _highlightScroller.clearKey();
          for (var i = 0; i < sections.length; i++) {
            final sectionInfo = sections[i];
            final day = sectionInfo.day;
            final schedules = grouped[day]!;
            final dayDate = sectionInfo.date;
            final dayDateLabel = dayDate == null ? '' : formatLongDate(dayDate);

            children.add(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: BracuSectionTitle(
                          title: formatWeekdayTitle(day),
                        ),
                      ),
                      if (dayDateLabel.isNotEmpty)
                        Text(
                          dayDateLabel,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: BracuPalette.textPrimary(context),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ...schedules.map((entry) {
                    final s = entry["schedule"] as section.ClassSchedule;
                    final code = entry["courseCode"];
                    final sectionName = entry["sectionName"];
                    final room = entry["roomNumber"];
                    final faculties = entry["faculties"] as String?;
                    final consumedSeat = entry["consumedSeat"] as int?;
                    final courseType = (entry["courseType"] as String?)?.trim();
                    final semesterSessionId =
                        entry["semesterSessionId"] as int?;
                    final isScrollTarget =
                        shouldHighlightCurrentSemester &&
                        scrollSchedule == s &&
                        scrollDateTime != null &&
                        dayDate != null &&
                        scrollDateTime.year == dayDate.year &&
                        scrollDateTime.month == dayDate.month &&
                        scrollDateTime.day == dayDate.day;
                    if (isScrollTarget) {
                      highlightToken =
                          '${sectionInfo.weekOffset}_${day}_${s.startTime}_${s.endTime}_$code';
                      _highlightScroller.ensureKey();
                    }
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: ScheduleEntryCard(
                        key: isScrollTarget ? _highlightScroller.key : null,
                        sectionName: sectionName?.toString(),
                        courseCode: '$code',
                        schedule: s,
                        isRamadan: isRamadan,
                        roomNumber: room?.toString(),
                        faculties: faculties,
                        consumedSeat: consumedSeat,
                        courseType: courseType,
                        highlighted: isScrollTarget,
                        onTap: () {
                          final semesterLabel = semesterSessionId == null
                              ? 'Current'
                              : formatSemesterFromSessionIdInt(
                                  semesterSessionId,
                                );
                          _openClassActionsSheet(
                            courseCode: '$code',
                            sectionName: sectionName?.toString() ?? '',
                            schedule: s,
                            isRamadan: isRamadan,
                            roomNumber: room?.toString(),
                            faculties: faculties,
                            consumedSeat: consumedSeat,
                            courseType: courseType,
                            semesterLabel: semesterLabel,
                          );
                        },
                      ),
                    );
                  }),
                  const SizedBox(height: 6),
                ],
              ),
            );
          }

          if (shouldHighlightCurrentSemester) {
            children.add(
              Padding(
                padding: const EdgeInsets.only(top: 2, bottom: 8),
                child: Center(
                  child: BracuActionButton(
                    onPressed: () {
                      setState(() {
                        _visibleWeekCount += 1;
                      });
                    },
                    label: 'Next week',
                  ),
                ),
              ),
            );
          }
          children.add(const SizedBox(height: 8));

          _highlightScroller.resetForToken(highlightToken);
          _attemptScrollToHighlight();

          return BracuRefreshList(
            onRefresh: _handleRefresh,
            controller: _scrollController,
            children: children,
          );
        },
      ),
    );
  }
}

class _ScheduleData {
  const _ScheduleData({
    required this.grouped,
    required this.scrollSchedule,
    required this.scrollDateTime,
    required this.isRamadan,
  });

  final Map<String, List<Map<String, dynamic>>> grouped;
  final section.ClassSchedule? scrollSchedule;
  final DateTime? scrollDateTime;
  final bool isRamadan;
}

class _RenderedScheduleSection {
  const _RenderedScheduleSection({
    required this.day,
    required this.date,
    required this.weekOffset,
  });

  final String day;
  final DateTime? date;
  final int weekOffset;
}
