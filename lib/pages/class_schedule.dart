import 'dart:async';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:preconnect/api/exam_map.dart';
import 'package:preconnect/api/schedule.dart';
import 'package:preconnect/model/section_info.dart' as section;
import 'package:preconnect/pages/shared_widgets/exam_filter.dart';
import 'package:preconnect/pages/shared_widgets/scroll_helper.dart';
import 'package:preconnect/pages/shared_widgets/entry_card.dart';
import 'package:preconnect/features/schedule/application/session_resolver.dart';
import 'package:preconnect/pages/shared_widgets/session_selector.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/app_storage.dart';
import 'package:preconnect/tools/storage_keys.dart';
import 'package:preconnect/tools/snapshot_store.dart';
import 'package:preconnect/tools/preload_cache.dart';
import 'package:preconnect/tools/refresh_bus.dart';
import 'package:preconnect/pages/shared_widgets/online_guard.dart';
import 'package:preconnect/tools/ramadan.dart';
import 'package:preconnect/tools/holiday.dart';
import 'package:preconnect/tools/time_utils.dart';

class ClassSchedulePage extends StatefulWidget {
  const ClassSchedulePage({super.key});

  static final ValueNotifier<int> jumpSignal = ValueNotifier<int>(0);

  static Future<void> preload({bool forceRefresh = false}) async {
    await _ClassScheduleState.preloadData(forceRefresh: forceRefresh);
  }

  static void requestJump() {
    jumpSignal.value++;
  }

  @override
  State<ClassSchedulePage> createState() => _ClassScheduleState();
}

class _ClassScheduleState extends State<ClassSchedulePage>
    with RefreshBusState {
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

  static final CachedPageController<_ScheduleData> cache =
      CachedPageController<_ScheduleData>(
        ({bool forceRefresh = false}) =>
            _ClassScheduleState._loadScheduleData(forceRefresh: forceRefresh),
      );

  late Future<_ScheduleData> _future;
  _ScheduleData? _latestData;
  final ScrollController _scrollController = ScrollController();
  late final HighlightScrollCoordinator _highlightScroll =
      HighlightScrollCoordinator(scrollController: _scrollController);
  int _visibleWeekCount = _initialVisibleWeekCount;
  bool _showDoneSections = false;
  HolidayStatus _holidayStatus = HolidayTiming.cachedStatus;

  @override
  void initState() {
    super.initState();
    final initialSyncData = cache.value ?? _loadScheduleDataSync();
    _latestData = initialSyncData;
    _future = initialSyncData != null
        ? Future<_ScheduleData>.value(initialSyncData)
        : preloadData();
    unawaited(_warmAndBind());
    unawaited(_loadHolidayStatus());
    unawaited(_updateSemesterName());
    ClassSchedulePage.jumpSignal.addListener(_onJumpRequested);
    cache.addListener(_onCacheUpdated);
    bindRefreshBus(_onRefreshSignal);
  }

  Future<void> _warmAndBind() async {
    if (_latestData != null) return;
    final currentSessionId = await resolveCurrentSessionSemesterId();
    final targetSessionId = _selectedSemesterSessionId ?? currentSessionId;
    if (targetSessionId == null) return;
    final data = await _loadSemesterSchedule(
      targetSessionId,
      forceRefresh: false,
    );
    if (!mounted) return;
    setState(() {
      _latestData = data;
      _future = Future<_ScheduleData>.value(data);
    });
  }

  static _ScheduleData? _loadScheduleDataSync([int? semesterSessionId]) {
    final sections = ScheduleService().getStudentSectionsSync(
      semesterSessionId,
    );
    if (sections == null || sections.isEmpty) return null;
    final currentSessionId = AppStorage.instance.getIntSync(
      StorageKeys.currentSessionSemesterId,
    );
    final targetSessionId = semesterSessionId ?? currentSessionId;
    final isCurrentSemester =
        targetSessionId == null || targetSessionId == currentSessionId;
    final overrides = targetSessionId != null
        ? ExamScheduleService().getOverridesForSemesterSync(targetSessionId)
        : const <String, ExamScheduleOverride>{};
    return _buildScheduleDataFromSectionsStatic(
      sections,
      shouldHighlightCurrentSemester: isCurrentSemester,
      isRamadan: false,
      examOverrides: overrides,
      holidayStatus: HolidayTiming.cachedStatus,
    );
  }

  static Future<_ScheduleData> preloadData({bool forceRefresh = false}) async {
    return cache.load(forceRefresh: forceRefresh);
  }

  static Future<_ScheduleData> _loadScheduleData({
    bool forceRefresh = false,
  }) async {
    final currentSessionSemesterId = forceRefresh
        ? null
        : await resolveCurrentSessionSemesterIdWithRetry();

    List<section.Section> sections = const <section.Section>[];
    if (currentSessionSemesterId != null) {
      sections = await ScheduleService().getUnifiedStudentSchedule(
        semesterSessionId: currentSessionSemesterId,
        forceRefresh: forceRefresh,
      );
    } else {
      sections =
          await JsonSnapshotStore.readSections() ?? const <section.Section>[];
    }

    final isRamadan = await RamadanTiming.isRamadan(forceRefresh: forceRefresh);
    final holidayStatus = await HolidayTiming.getTodayStatus(
      forceRefresh: forceRefresh,
    );

    final examOverrides = sections.isEmpty
        ? const <String, ExamScheduleOverride>{}
        : await ExamScheduleService().getOverridesForSections(
            sections,
            forceRefresh: forceRefresh,
            forcedSemesterSessionId: currentSessionSemesterId,
          );

    return _buildScheduleDataFromSectionsStatic(
      sections,
      shouldHighlightCurrentSemester: true,
      isRamadan: isRamadan,
      examOverrides: examOverrides,
      holidayStatus: holidayStatus,
    );
  }

  @override
  void dispose() {
    ClassSchedulePage.jumpSignal.removeListener(_onJumpRequested);
    cache.removeListener(_onCacheUpdated);
    _scrollController.dispose();
    unbindRefreshBus(_onRefreshSignal);
    super.dispose();
  }

  void _onCacheUpdated() {
    if (!mounted) return;
    final val = cache.value;
    if (val != null) {
      setState(() {
        _latestData = val;
        _future = Future<_ScheduleData>.value(val);
      });
    }
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
    _highlightScroll.resetScrollState();
    if (!mounted) return;
    setState(() {
      _visibleWeekCount = _initialVisibleWeekCount;
    });
  }

  void _toggleDoneView() {
    setState(() {
      _showDoneSections = !_showDoneSections;
      _highlightScroll.resetScrollState();
      _visibleWeekCount = _initialVisibleWeekCount;
    });
  }

  Future<void> _loadHolidayStatus({bool forceRefresh = false}) async {
    final status = await HolidayTiming.getTodayStatus(
      forceRefresh: forceRefresh,
    );
    if (!mounted) return;
    setState(() {
      _holidayStatus = status;
    });
  }

  static _ScheduleData _buildScheduleDataFromSectionsStatic(
    List<section.Section> sections, {
    required bool shouldHighlightCurrentSemester,
    required bool isRamadan,
    required Map<String, ExamScheduleOverride> examOverrides,
    HolidayStatus? holidayStatus,
  }) {
    if (sections.isEmpty) {
      return _ScheduleData(
        grouped: {},
        sections: sections,
        examOverrides: examOverrides,
        scrollSchedule: null,
        scrollDateTime: null,
        isRamadan: isRamadan,
      );
    }

    final Map<String, List<_ScheduleRow>> grouped = {};
    section.ClassSchedule? scrollSchedule;
    DateTime? scrollDateTime;
    final now = DateTime.now();
    final seen = <String>{};

    for (final section in sections) {
      for (final classSchedule in section.sectionSchedule.classSchedules) {
        final key =
            '${section.courseCode}|${section.sectionName}|${classSchedule.day}|${classSchedule.startTime}|${classSchedule.endTime}|${section.roomNumber}';
        if (!seen.add(key)) {
          continue;
        }
        grouped.putIfAbsent(classSchedule.day, () => []);
        grouped[classSchedule.day]!.add(
          _ScheduleRow.fromSection(section, classSchedule),
        );

        if (shouldHighlightCurrentSemester) {
          final candidate = _nextOccurrenceStatic(
            day: classSchedule.day,
            startTime: classSchedule.startTime,
            endTime: classSchedule.endTime,
            startDate: section.sectionSchedule.classStartDate,
            endDate: section.sectionSchedule.classEndDate,
            isRamadan: isRamadan,
            now: now,
            holidayStatus: holidayStatus,
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
        final aSchedule = a.schedule;
        final bSchedule = b.schedule;
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
      sections: sections,
      examOverrides: examOverrides,
      scrollSchedule: scrollSchedule,
      scrollDateTime: scrollDateTime,
      isRamadan: isRamadan,
    );
  }

  static DateTime? _nextOccurrenceStatic({
    required String day,
    required String startTime,
    required String endTime,
    String? startDate,
    String? endDate,
    required bool isRamadan,
    required DateTime now,
    HolidayStatus? holidayStatus,
  }) {
    final targetWeekday = AppTime.weekdayFromName(day);
    if (targetWeekday == null) return null;

    final adjusted = RamadanTiming.adjustRange(
      startTime,
      endTime,
      isRamadan: isRamadan,
    );

    final startParsed = AppTime.parseHourMinute(adjusted.startTime);
    if (startParsed == null) return null;
    final (startHour, startMinute) = startParsed;
    final startMinutes = startHour * 60 + startMinute;

    final endParsed = AppTime.parseHourMinute(adjusted.endTime);
    final endHour = endParsed?.$1 ?? 0;
    final endMinute = endParsed?.$2 ?? 0;
    final endMinutes = endHour * 60 + endMinute;

    var candidate = nextWeeklyOccurrence(
      weekday: targetWeekday,
      startMinutes: startMinutes,
      endMinutes: endMinutes,
      now: now,
    );

    final s = AppTime.parseDate(startDate);
    final e = AppTime.parseDate(endDate);
    while (candidate != null &&
        s != null &&
        candidate.isBefore(DateTime(s.year, s.month, s.day))) {
      candidate = candidate.add(const Duration(days: 7));
    }
    while (candidate != null &&
        holidayStatus != null &&
        holidayStatus.isHolidayOn(candidate)) {
      candidate = candidate.add(const Duration(days: 7));
    }
    if (candidate != null &&
        e != null &&
        candidate.isAfter(DateTime(e.year, e.month, e.day, 23, 59, 59))) {
      return null;
    }

    return candidate;
  }

  Future<void> _handleRefresh({bool notify = true}) async {
    if (!await ensureOnline(context, notify: notify)) {
      return;
    }
    if (!mounted) return;
    final currentSessionId = await resolveCurrentSessionSemesterId(
      forceRefresh: _selectedSemesterSessionId == null,
    );
    final targetSemesterId = _selectedSemesterSessionId ?? currentSessionId;
    setState(() {
      _highlightScroll.resetScrollState();
      _visibleWeekCount = _initialVisibleWeekCount;
      _future = targetSemesterId != null
          ? _loadSemesterSchedule(targetSemesterId, forceRefresh: true)
          : preloadData(forceRefresh: true);
    });
    await Future.wait<void>([
      _future.then<void>((_) {}),
      _loadHolidayStatus(forceRefresh: true),
    ]);
    if (notify) {
      RefreshBus.instance.notify(reason: 'class_schedule');
    }
  }

  DateTime? _findMaxFinalExamDate(
    List<section.Section> studentSections,
    Map<String, ExamScheduleOverride> overrides,
  ) {
    DateTime? maxDate;
    final examService = ExamScheduleService();
    for (final s in studentSections) {
      final resolved = examService.resolveSection(
        section: s,
        overrides: overrides,
      );
      final dateStr = resolved.finalDate;
      if (dateStr != null && dateStr.isNotEmpty) {
        final dt = AppTime.parseDateTime(dateStr, resolved.finalStartTime);
        if (dt != null && (maxDate == null || dt.isAfter(maxDate))) {
          maxDate = dt;
        }
      }
      final endDate = AppTime.parseDate(s.sectionSchedule.classEndDate);
      if (endDate != null) {
        final dt = DateTime(
          endDate.year,
          endDate.month,
          endDate.day,
          23,
          59,
          59,
        );
        if (maxDate == null || dt.isAfter(maxDate)) maxDate = dt;
      }
    }
    return maxDate;
  }

  List<_RenderedScheduleSection> _buildRenderedSections(
    Map<String, List<_ScheduleRow>> grouped, {
    required bool shouldHighlightCurrentSemester,
    DateTime? maxFinalExamDate,
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
    final cutoff = maxFinalExamDate != null
        ? DateTime(
            maxFinalExamDate.year,
            maxFinalExamDate.month,
            maxFinalExamDate.day,
            23,
            59,
            59,
          )
        : null;

    for (var dayOffset = 0; dayOffset < totalDays; dayOffset++) {
      final date = today.add(Duration(days: dayOffset));
      if (cutoff != null && date.isAfter(cutoff)) break;
      final day = _weekdayNames[date.weekday - 1];
      final list = grouped[day];
      if (list == null || !list.any((s) => s.isActiveOn(date))) continue;
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

  String? _selectedSemesterName;

  void _onSemesterSessionChanged(SemesterSessionItem item) {
    final changed = _selectedSemesterSessionId != item.semesterSessionId;
    if (_selectedSemesterName != item.description || changed) {
      final syncData = _loadScheduleDataSync(item.semesterSessionId);
      setState(() {
        _selectedSemesterSessionId = item.semesterSessionId;
        _selectedSemesterName = item.description;
        _latestData = syncData;
        _future = _loadSemesterSchedule(item.semesterSessionId);
      });
    }
  }

  Future<_ScheduleData> _loadSemesterSchedule(
    int semesterSessionId, {
    bool forceRefresh = false,
  }) async {
    final sections = await ScheduleService().getUnifiedStudentSchedule(
      semesterSessionId: semesterSessionId,
      forceRefresh: forceRefresh,
    );
    final isRamadan = await RamadanTiming.isRamadan();
    final examOverrides = sections.isEmpty
        ? const <String, ExamScheduleOverride>{}
        : await ExamScheduleService().getOverridesForSections(
            sections,
            forceRefresh: forceRefresh,
            forcedSemesterSessionId: semesterSessionId,
          );
    final currentSessionId = await resolveCurrentSessionSemesterId();
    final isCurrentSemester =
        currentSessionId == null || semesterSessionId == currentSessionId;
    final holidayStatus = isCurrentSemester
        ? await HolidayTiming.getTodayStatus(forceRefresh: forceRefresh)
        : HolidayStatus.empty;
    final data = _buildScheduleDataFromSectionsStatic(
      sections,
      shouldHighlightCurrentSemester: isCurrentSemester,
      isRamadan: isRamadan,
      examOverrides: examOverrides,
      holidayStatus: holidayStatus,
    );
    if (mounted) {
      setState(() {
        _latestData = data;
      });
    }
    return data;
  }

  int? _selectedSemesterSessionId;

  Future<void> _updateSemesterName([int? semesterSessionId]) async {
    final item = await ScheduleService().resolveSemesterSessionItem(
      semesterSessionId,
    );
    if (item != null && mounted) {
      setState(() {
        _selectedSemesterName = item.description;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final subtitleText = _selectedSemesterName ?? '';

    final currentSessionId = AppStorage.instance.getIntSync(
      StorageKeys.currentSessionSemesterId,
    );
    final isCurrentSemester =
        _selectedSemesterSessionId == null ||
        currentSessionId == null ||
        _selectedSemesterSessionId == currentSessionId;

    return AppPageScaffold(
      title: 'Schedules',
      subtitle: subtitleText,
      icon: Icons.schedule_outlined,
      actions: [
        if (isCurrentSemester)
          AppSelectChip(
            icon: Icons.history_rounded,
            selected: _showDoneSections,
            compact: true,
            showArrow: false,
            showBorder: false,
            onTap: _toggleDoneView,
          ),
        SemesterSessionSelector(
          selectedSemesterSessionId: _selectedSemesterSessionId,
          onSessionChanged: _onSemesterSessionChanged,
          iconOnly: true,
        ),
      ],
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
          if (snapshot.connectionState == ConnectionState.waiting &&
              data == null) {
            return buildRefreshLoadingState(onRefresh: _handleRefresh);
          }
          final grouped = data?.grouped ?? {};
          final studentSections = data?.sections ?? const <section.Section>[];
          final overrides =
              data?.examOverrides ?? const <String, ExamScheduleOverride>{};
          final scrollSchedule = data?.scrollSchedule;
          final scrollDateTime = data?.scrollDateTime;
          final shouldHighlightCurrentSemester =
              isCurrentSemester && !_showDoneSections;
          final isRamadan = data?.isRamadan ?? false;
          final finishedSectionKeys =
              CourseSectionExamFilter.finishedSectionKeys(
                studentSections,
                overrides,
              );
          final visibleGrouped = <String, List<_ScheduleRow>>{};
          for (final entry in grouped.entries) {
            final filteredEntries = entry.value
                .where((item) {
                  if (!isCurrentSemester) return true;
                  final key = ExamMapService.sectionKey(
                    courseCode: item.courseCode,
                    sectionName: item.sectionName,
                  );
                  final isDone = finishedSectionKeys.contains(key);
                  return _showDoneSections ? isDone : !isDone;
                })
                .toList(growable: false);
            if (filteredEntries.isNotEmpty) {
              visibleGrouped[entry.key] = filteredEntries;
            }
          }
          if (grouped.isEmpty) {
            return buildRefreshEmptyState(
              onRefresh: _handleRefresh,
              message: 'No schedule data available',
            );
          }

          final maxFinalExamDate = _findMaxFinalExamDate(
            studentSections,
            overrides,
          );
          var renderedSections = _buildRenderedSections(
            visibleGrouped,
            shouldHighlightCurrentSemester: shouldHighlightCurrentSemester,
            maxFinalExamDate: maxFinalExamDate,
          );

          if (visibleGrouped.isEmpty ||
              (shouldHighlightCurrentSemester && renderedSections.isEmpty)) {
            return buildRefreshEmptyState(
              onRefresh: _handleRefresh,
              message: _showDoneSections
                  ? 'No done class available'
                  : 'No active class available',
            );
          }

          final children = <Widget>[];
          final now = DateTime.now();
          final today = DateTime(now.year, now.month, now.day);
          final todayWeekday = _weekdayNames[now.weekday - 1];
          final hasClassesToday = visibleGrouped.containsKey(todayWeekday);
          final holidayStatus = isCurrentSemester
              ? _holidayStatus
              : HolidayStatus.empty;
          final isTodayHoliday =
              holidayStatus.isTodayHoliday || holidayStatus.isHolidayOn(now);
          final todayScheduleStatus = AppTodayScheduleStatus.resolve(
            holidayStatus: holidayStatus,
          );

          if (!_showDoneSections && isTodayHoliday) {
            renderedSections = renderedSections
                .where((sectionInfo) {
                  final date = sectionInfo.date;
                  return date == null ||
                      date.year != now.year ||
                      date.month != now.month ||
                      date.day != now.day;
                })
                .toList(growable: false);
          }

          if (!_showDoneSections && (isTodayHoliday || !hasClassesToday)) {
            final todayDateLabel = formatLongDate(now);
            children.add(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: AppSectionTitle(
                          title: 'Today is ${formatWeekdayTitle(todayWeekday)}',
                        ),
                      ),
                      Text(
                        todayDateLabel,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppPalette.textPrimary(context),
                        ),
                      ),
                    ],
                  ),
                  const Gap(12),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: AppScheduleTile(
                      title: todayScheduleStatus.title,
                      subtitle: todayScheduleStatus.subtitle,
                      badge: todayScheduleStatus.badge,
                      color: AppPalette.primary,
                    ),
                  ),
                  const Gap(6),
                ],
              ),
            );
          }

          String? highlightToken;
          int? highlightIndex;
          var cardIndex = 0;
          final totalCards = renderedSections.fold<int>(0, (sum, sectionInfo) {
            final daySchedules = visibleGrouped[sectionInfo.day] ?? const [];
            final dayDate = sectionInfo.date;
            if (dayDate == null) return sum + daySchedules.length;
            if (!_showDoneSections && holidayStatus.isHolidayOn(dayDate)) {
              return sum + 1;
            }
            return sum +
                daySchedules.where((s) => s.isActiveOn(dayDate)).length;
          });
          _highlightScroll.clearHighlightKey();
          for (var i = 0; i < renderedSections.length; i++) {
            final sectionInfo = renderedSections[i];
            final day = sectionInfo.day;
            final schedules = visibleGrouped[day]!;
            final dayDate = sectionInfo.date;
            final activeSchedules = dayDate != null
                ? schedules
                      .where((s) => s.isActiveOn(dayDate))
                      .toList(growable: false)
                : schedules;
            if (activeSchedules.isEmpty) continue;
            final dayDateLabel = dayDate == null ? '' : formatLongDate(dayDate);
            final holidayName = !_showDoneSections && dayDate != null
                ? holidayStatus.holidayNameOn(dayDate)
                : null;
            final isDayOff = holidayName != null;

            final scheduleWidgets = <Widget>[];
            if (isDayOff) {
              scheduleWidgets.add(
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: AppScheduleTile(
                    title: 'University Holiday',
                    subtitle:
                        (holidayName.isNotEmpty &&
                            holidayName.toLowerCase() != 'university holiday')
                        ? holidayName
                        : 'Enjoy your day off.',
                    badge: 'OFF',
                    color: AppPalette.primary,
                  ),
                ),
              );
              cardIndex++;
            } else {
              for (final entry in activeSchedules) {
                final s = entry.schedule;
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
                      '${sectionInfo.weekOffset}_${day}_${s.startTime}_${s.endTime}_${entry.courseCode}';
                  highlightIndex ??= cardIndex;
                }
                final isHighlighted = isScrollTarget;
                _highlightScroll.markHighlighted(isHighlighted);
                scheduleWidgets.add(
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: RepaintBoundary(
                      child: ScheduleEntryCard(
                        key: isHighlighted
                            ? _highlightScroll.highlightKey
                            : null,
                        sectionName: entry.sectionName,
                        courseCode: entry.courseCode,
                        schedule: s,
                        isRamadan: isRamadan,
                        roomNumber: entry.roomNumber,
                        faculties: entry.faculties,
                        consumedSeat: entry.consumedSeat,
                        courseType: entry.courseType.trim(),
                        highlighted: isHighlighted,
                      ),
                    ),
                  ),
                );
                cardIndex++;
              }
            }

            children.add(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: AppSectionTitle(title: formatWeekdayTitle(day)),
                      ),
                      if (dayDateLabel.isNotEmpty)
                        Text(
                          dayDateLabel,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppPalette.textPrimary(context),
                          ),
                        ),
                    ],
                  ),
                  const Gap(12),
                  ...scheduleWidgets,
                  const Gap(6),
                ],
              ),
            );
          }

          final cutoff = maxFinalExamDate != null
              ? DateTime(
                  maxFinalExamDate.year,
                  maxFinalExamDate.month,
                  maxFinalExamDate.day,
                  23,
                  59,
                  59,
                )
              : null;
          final lastDate = renderedSections.isNotEmpty
              ? renderedSections.last.date
              : null;
          final canLoadMoreWeeks =
              shouldHighlightCurrentSemester &&
              renderedSections.isNotEmpty &&
              (cutoff == null ||
                  (!now.isAfter(cutoff) &&
                      !today
                          .add(Duration(days: _visibleWeekCount * 7))
                          .isAfter(cutoff) &&
                      (lastDate == null || lastDate.isBefore(cutoff))));

          if (canLoadMoreWeeks) {
            children.add(
              Padding(
                padding: const EdgeInsets.only(top: 2, bottom: 8),
                child: Center(
                  child: AppActionButton(
                    onPressed: () {
                      setState(() {
                        _visibleWeekCount += 1;
                      });
                    },
                    label: 'Next Week',
                  ),
                ),
              ),
            );
          }
          children.add(const Gap(8));

          if (highlightToken != null) {
            unawaited(
              _highlightScroll.scrollToTarget(
                targetToken: highlightToken,
                targetIndex: highlightIndex,
                itemCount: totalCards,
                onRetryBuild: () {
                  if (mounted) {
                    setState(() {});
                  }
                },
              ),
            );
          }

          return AppRefreshList(
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
    required this.sections,
    required this.examOverrides,
    required this.scrollSchedule,
    required this.scrollDateTime,
    required this.isRamadan,
  });

  final Map<String, List<_ScheduleRow>> grouped;
  final List<section.Section> sections;
  final Map<String, ExamScheduleOverride> examOverrides;
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

class _ScheduleRow {
  const _ScheduleRow({
    required this.schedule,
    required this.courseCode,
    required this.sectionName,
    required this.roomNumber,
    required this.faculties,
    required this.consumedSeat,
    required this.capacity,
    required this.courseType,
    required this.semesterSessionId,
    required this.startDate,
    required this.endDate,
  });

  factory _ScheduleRow.fromSection(
    section.Section value,
    section.ClassSchedule schedule,
  ) {
    return _ScheduleRow(
      schedule: schedule,
      courseCode: value.courseCode,
      sectionName: value.sectionName,
      roomNumber: value.roomNumber,
      faculties: value.faculties,
      consumedSeat: value.consumedSeat,
      capacity: value.capacity,
      courseType: value.courseType,
      semesterSessionId: value.semesterSessionId,
      startDate: value.sectionSchedule.classStartDate,
      endDate: value.sectionSchedule.classEndDate,
    );
  }

  final section.ClassSchedule schedule;
  final String courseCode;
  final String sectionName;
  final String? roomNumber;
  final String? faculties;
  final int? consumedSeat;
  final int? capacity;
  final String courseType;
  final int semesterSessionId;
  final String startDate;
  final String endDate;

  bool isActiveOn(DateTime date) {
    final s = AppTime.parseDate(startDate);
    final e = AppTime.parseDate(endDate);
    if (s != null && date.isBefore(DateTime(s.year, s.month, s.day))) {
      return false;
    }
    if (e != null &&
        date.isAfter(DateTime(e.year, e.month, e.day, 23, 59, 59))) {
      return false;
    }
    return true;
  }
}
