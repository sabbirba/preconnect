import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:preconnect/api/exam_map.dart';
import 'package:preconnect/api/schedule.dart';
import 'package:preconnect/model/section_info.dart' as section;
import 'package:preconnect/pages/shared_widgets/exam_filter.dart';
import 'package:preconnect/pages/shared_widgets/scroll_helper.dart';
import 'package:preconnect/pages/shared_widgets/entry_card.dart';
import 'package:preconnect/pages/shared_widgets/session_helper.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/app_storage.dart';
import 'package:preconnect/tools/storage_keys.dart';
import 'package:preconnect/tools/snapshot_store.dart';
import 'package:preconnect/tools/preload_cache.dart';
import 'package:preconnect/tools/refresh_bus.dart';
import 'package:preconnect/tools/ramadan.dart';
import 'package:preconnect/tools/time_utils.dart';

class ClassSchedule extends StatefulWidget {
  const ClassSchedule({super.key});

  static final ValueNotifier<int> jumpSignal = ValueNotifier<int>(0);

  static Future<void> preload({bool forceRefresh = false}) async {
    await _ClassScheduleState.preloadData(forceRefresh: forceRefresh);
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

  @override
  void initState() {
    super.initState();
    _latestData = cache.value ?? _loadScheduleDataSync();
    _future = cache.value == null
        ? preloadData()
        : Future<_ScheduleData>.value(cache.value!);
    unawaited(_warmAndBind());
    ClassSchedule.jumpSignal.addListener(_onJumpRequested);
    bindRefreshBus(_onRefreshSignal);
  }

  Future<void> _warmAndBind() async {
    final data = await preloadData();
    if (!mounted) return;
    setState(() {
      _latestData = data;
      _future = Future<_ScheduleData>.value(data);
    });
  }

  static _ScheduleData? _loadScheduleDataSync() {
    try {
      final raw = AppStorage.instance.getStringSync(StorageKeys.alarmsSnapshot);
      if (raw == null || raw.trim().isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final sectionsRaw = decoded['sections'];
      if (sectionsRaw is! List) return null;
      final sections = sectionsRaw
          .whereType<Map>()
          .map(
            (entry) => section.Section.fromJson(entry.cast<String, dynamic>()),
          )
          .toList(growable: false);
      if (sections.isEmpty) return null;
      final isRamadan = decoded['isRamadan'] == true;
      return _buildScheduleDataFromSectionsStatic(
        sections,
        shouldHighlightCurrentSemester: true,
        isRamadan: isRamadan,
        examOverrides: const <String, ExamScheduleOverride>{},
      );
    } catch (_) {
      return null;
    }
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

    List<section.Section>? sections;
    bool isRamadan = false;

    if (currentSessionSemesterId != null) {
      final service = ScheduleService();
      final cachedJson = await service.getCachedStudentScheduleForSemester(
        semesterSessionId: currentSessionSemesterId,
      );
      final jsonString =
          cachedJson ??
          (forceRefresh
              ? await service.fetchStudentScheduleForSemester(
                  semesterSessionId: currentSessionSemesterId,
                  fromGet: true,
                )
              : await service.getStudentScheduleForSemester(
                  semesterSessionId: currentSessionSemesterId,
                ));
      sections = service.parseStudentSections(
        jsonString,
        semesterSessionId: currentSessionSemesterId,
      );
      isRamadan = await RamadanTiming.isRamadan(forceRefresh: forceRefresh);
      if (sections.isNotEmpty) {
        unawaited(
          JsonSnapshotStore.updateSections(sections, isRamadan: isRamadan),
        );
      }
    }

    if (sections == null || sections.isEmpty) {
      sections = await JsonSnapshotStore.readSections();
      final existingMap = await JsonSnapshotStore.read<Map<String, dynamic>>(
        key: StorageKeys.alarmsSnapshot,
        decode: (decoded) => decoded,
      );
      isRamadan = existingMap?['isRamadan'] == true;
    }

    sections ??= const <section.Section>[];

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
    _highlightScroll.resetScrollState();
    if (mounted) {
      setState(() {
        _visibleWeekCount = _initialVisibleWeekCount;
      });
    }
  }

  void _toggleDoneView() {
    setState(() {
      _showDoneSections = !_showDoneSections;
      _highlightScroll.resetScrollState();
      _visibleWeekCount = _initialVisibleWeekCount;
    });
  }

  static _ScheduleData _buildScheduleDataFromSectionsStatic(
    List<section.Section> sections, {
    required bool shouldHighlightCurrentSemester,
    required bool isRamadan,
    required Map<String, ExamScheduleOverride> examOverrides,
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
    final nowMinutes = now.hour * 60 + now.minute;

    for (final section in sections) {
      for (final classSchedule in section.sectionSchedule.classSchedules) {
        grouped.putIfAbsent(classSchedule.day, () => []);
        grouped[classSchedule.day]!.add(
          _ScheduleRow.fromSection(section, classSchedule),
        );

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
    if (!mounted) return;
    setState(() {
      _highlightScroll.resetScrollState();
      _visibleWeekCount = _initialVisibleWeekCount;
      _future = preloadData(forceRefresh: true);
    });
    await _future;
    if (notify) {
      RefreshBus.instance.notify(reason: 'class_schedule');
    }
  }

  List<_RenderedScheduleSection> _buildRenderedSections(
    Map<String, List<_ScheduleRow>> grouped, {
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
      actions: [
        BracuSelectChip(
          icon: Icons.history_rounded,
          selected: _showDoneSections,
          compact: true,
          showArrow: false,
          showBorder: false,
          onTap: _toggleDoneView,
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
          const shouldHighlightCurrentSemester = true;
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

          final renderedSections = _buildRenderedSections(
            visibleGrouped,
            shouldHighlightCurrentSemester: shouldHighlightCurrentSemester,
          );

          if (visibleGrouped.isEmpty) {
            return buildRefreshEmptyState(
              onRefresh: _handleRefresh,
              message: _showDoneSections
                  ? 'No done classes available'
                  : 'No active classes available',
            );
          }

          final children = <Widget>[];
          String? highlightToken;
          int? highlightIndex;
          var cardIndex = 0;
          final totalCards = renderedSections.fold<int>(0, (sum, sectionInfo) {
            final daySchedules = visibleGrouped[sectionInfo.day] ?? const [];
            return sum + daySchedules.length;
          });
          _highlightScroll.clearHighlightKey();
          for (var i = 0; i < renderedSections.length; i++) {
            final sectionInfo = renderedSections[i];
            final day = sectionInfo.day;
            final schedules = visibleGrouped[day]!;
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
                  const Gap(10),
                  ...(() {
                    final scheduleWidgets = <Widget>[];
                    for (final entry in schedules) {
                      final s = entry.schedule;
                      final code = entry.courseCode;
                      final sectionName = entry.sectionName;
                      final room = entry.roomNumber;
                      final faculties = entry.faculties;
                      final consumedSeat = entry.consumedSeat;
                      final courseType = entry.courseType.trim();
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
                        highlightIndex ??= cardIndex;
                      }
                      final isHighlighted = isScrollTarget;
                      _highlightScroll.markHighlighted(isHighlighted);
                      scheduleWidgets.add(
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: ScheduleEntryCard(
                            key: isHighlighted
                                ? _highlightScroll.highlightKey
                                : null,
                            sectionName: sectionName,
                            courseCode: code,
                            schedule: s,
                            isRamadan: isRamadan,
                            roomNumber: room,
                            faculties: faculties,
                            consumedSeat: consumedSeat,
                            courseType: courseType,
                            highlighted: isHighlighted,
                          ),
                        ),
                      );
                      cardIndex++;
                    }
                    return scheduleWidgets;
                  })(),
                  const Gap(6),
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
}
