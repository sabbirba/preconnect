import 'dart:async';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import 'package:preconnect/api/exam_map.dart';
import 'package:preconnect/api/schedule.dart';
import 'package:preconnect/model/section_info.dart';
import 'package:preconnect/pages/shared_widgets/scroll_helper.dart';
import 'package:preconnect/features/schedule/application/session_resolver.dart';
import 'package:preconnect/pages/shared_widgets/session_selector.dart';
import 'package:preconnect/pages/shared_widgets/exam_card.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/string_utils.dart';
import 'package:preconnect/tools/app_storage.dart';
import 'package:preconnect/tools/storage_keys.dart';
import 'package:preconnect/tools/exam_visibility.dart';
import 'package:preconnect/tools/snapshot_store.dart';
import 'package:preconnect/tools/preload_cache.dart';
import 'package:preconnect/tools/refresh_bus.dart';
import 'package:preconnect/pages/shared_widgets/online_guard.dart';
import 'package:preconnect/tools/time_utils.dart';

class ExamSchedule extends StatefulWidget {
  const ExamSchedule({super.key});

  static final ValueNotifier<int> jumpSignal = ValueNotifier<int>(0);

  static Future<void> preload({bool forceRefresh = false}) async {
    await _ExamScheduleState.preloadData(forceRefresh: forceRefresh);
  }

  static void requestJump() {
    jumpSignal.value++;
  }

  @override
  State<ExamSchedule> createState() => _ExamScheduleState();
}

class _ExamScheduleState extends State<ExamSchedule> with RefreshBusState {
  static final CachedPageController<_ExamScheduleData> cache =
      CachedPageController<_ExamScheduleData>(
        ({bool forceRefresh = false}) =>
            _ExamScheduleState._loadExamData(forceRefresh: forceRefresh),
      );

  late Future<_ExamScheduleData> _future;
  _ExamScheduleData? _latestData;
  final ScrollController _scrollController = ScrollController();
  late final HighlightScrollCoordinator _highlightScroll =
      HighlightScrollCoordinator(scrollController: _scrollController);
  int? _currentSessionSemesterId;
  bool _showDoneExams = false;
  _ExamScheduleData? _resolvedForData;
  bool? _resolvedForShowDone;
  bool? _resolvedForIsPastSemester;
  _ResolvedExamLists? _resolvedListsCache;

  @override
  void initState() {
    super.initState();
    final initialSyncData = cache.value ?? _loadExamScheduleDataSync();
    _latestData = initialSyncData;
    _future = initialSyncData != null
        ? Future<_ExamScheduleData>.value(initialSyncData)
        : _initializeExamSchedule();
    unawaited(_loadCurrentSessionSemesterId());
    unawaited(_warmAndBind());
    unawaited(_updateSemesterName());
    ExamSchedule.jumpSignal.addListener(_onJumpRequested);
    cache.addListener(_onCacheUpdated);
    bindRefreshBus(_onRefreshSignal);
  }

  Future<void> _warmAndBind() async {
    if (_latestData != null) return;
    final data = await _fetchExamData(forceRefresh: false);
    if (!mounted) return;
    setState(() {
      _latestData = data;
      _future = Future<_ExamScheduleData>.value(data);
    });
  }

  static Future<_ExamScheduleData> preloadData({
    bool forceRefresh = false,
  }) async {
    return cache.load(forceRefresh: forceRefresh);
  }

  static Future<_ExamScheduleData> _loadExamData({
    bool forceRefresh = false,
  }) async {
    final currentSessionSemesterId =
        await resolveCurrentSessionSemesterIdWithRetry();

    List<Section> sections = const <Section>[];
    if (currentSessionSemesterId != null) {
      sections = await ScheduleService().getUnifiedStudentSchedule(
        semesterSessionId: currentSessionSemesterId,
        forceRefresh: forceRefresh,
      );
    } else {
      sections = await JsonSnapshotStore.readSections() ?? const <Section>[];
    }

    final overrides = sections.isEmpty
        ? const <String, ExamScheduleOverride>{}
        : await ExamScheduleService().getOverridesForSections(
            sections,
            forceRefresh: forceRefresh,
            forcedSemesterSessionId: currentSessionSemesterId,
          );

    return _ExamScheduleData(sections: sections, overrides: overrides);
  }

  Future<_ExamScheduleData> _initializeExamSchedule() async {
    unawaited(_loadCurrentSessionSemesterId());
    return _fetchExamData();
  }

  @override
  void dispose() {
    ExamSchedule.jumpSignal.removeListener(_onJumpRequested);
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
        _future = Future<_ExamScheduleData>.value(val);
      });
    }
  }

  void _onRefreshSignal() {
    if (!mounted) return;
    if (isRefreshingFrom('exam_schedule')) {
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
      _resolvedListsCache = null;
    });
  }

  void _toggleExamView() {
    setState(() {
      _showDoneExams = !_showDoneExams;
      _resolvedListsCache = null;
      _highlightScroll.resetScrollState();
    });
  }

  Future<_ExamScheduleData> _fetchExamData({bool forceRefresh = false}) async {
    final targetSemesterSessionId =
        _selectedSemesterSessionId ??
        _currentSessionSemesterId ??
        await resolveCurrentSessionSemesterIdWithRetry();

    List<Section> sections = const <Section>[];
    if (targetSemesterSessionId != null) {
      sections = await ScheduleService().getUnifiedStudentSchedule(
        semesterSessionId: targetSemesterSessionId,
        forceRefresh: forceRefresh,
      );
    } else {
      sections = await JsonSnapshotStore.readSections() ?? const <Section>[];
    }

    final overrides = sections.isEmpty
        ? const <String, ExamScheduleOverride>{}
        : await ExamScheduleService().getOverridesForSections(
            sections,
            forceRefresh: forceRefresh,
            forcedSemesterSessionId: targetSemesterSessionId,
          );

    final data = _ExamScheduleData(sections: sections, overrides: overrides);
    cache.value = data;
    if (mounted) {
      setState(() {
        _latestData = data;
      });
    }
    return data;
  }

  Future<void> _loadCurrentSessionSemesterId() async {
    final currentSessionSemesterId =
        await resolveCurrentSessionSemesterIdWithRetry();
    if (!mounted || currentSessionSemesterId == null) return;
    if (_currentSessionSemesterId == currentSessionSemesterId) return;
    setState(() {
      _currentSessionSemesterId = currentSessionSemesterId;
    });
    if (_selectedSemesterSessionId == null) {
      unawaited(_handleRefresh(notify: false));
    }
  }

  Future<void> _handleRefresh({bool notify = true}) async {
    if (!await ensureOnline(context, notify: notify)) {
      return;
    }
    if (!mounted) return;
    final targetSemesterId =
        _selectedSemesterSessionId ?? _currentSessionSemesterId;
    setState(() {
      _future = targetSemesterId != null
          ? _loadSemesterExamSchedule(targetSemesterId, forceRefresh: true)
          : preloadData(forceRefresh: true);
    });
    await _future;
    if (notify) {
      RefreshBus.instance.notify(reason: 'exam_schedule');
    }
  }

  static _ExamScheduleData? _loadExamScheduleDataSync([
    int? semesterSessionId,
  ]) {
    final targetSessionId =
        semesterSessionId ??
        AppStorage.instance.getIntSync(StorageKeys.currentSessionSemesterId);
    final sections = ScheduleService().getStudentSectionsSync(targetSessionId);
    if (sections == null || sections.isEmpty) return null;
    final overrides = targetSessionId != null
        ? ExamScheduleService().getOverridesForSemesterSync(targetSessionId)
        : const <String, ExamScheduleOverride>{};
    return _ExamScheduleData(sections: sections, overrides: overrides);
  }

  String? _selectedSemesterName;

  void _onSemesterSessionChanged(SemesterSessionItem item) {
    final changed = _selectedSemesterSessionId != item.semesterSessionId;
    if (_selectedSemesterName != item.description || changed) {
      final syncData = _loadExamScheduleDataSync(item.semesterSessionId);
      setState(() {
        _selectedSemesterSessionId = item.semesterSessionId;
        _selectedSemesterName = item.description;
        _resolvedListsCache = null;
        _latestData = syncData;
        _future = _loadSemesterExamSchedule(item.semesterSessionId);
      });
    }
  }

  Future<_ExamScheduleData> _loadSemesterExamSchedule(
    int semesterSessionId, {
    bool forceRefresh = false,
  }) async {
    final sections = await ScheduleService().getUnifiedStudentSchedule(
      semesterSessionId: semesterSessionId,
      forceRefresh: forceRefresh,
    );
    final overrides = sections.isEmpty
        ? const <String, ExamScheduleOverride>{}
        : await ExamScheduleService().getOverridesForSections(
            sections,
            forceRefresh: forceRefresh,
            forcedSemesterSessionId: semesterSessionId,
          );
    final data = _ExamScheduleData(sections: sections, overrides: overrides);
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

    final isCurrentSemester =
        _selectedSemesterSessionId == null ||
        _currentSessionSemesterId == null ||
        _selectedSemesterSessionId == _currentSessionSemesterId;

    return BracuPageScaffold(
      title: 'Schedules',
      subtitle: subtitleText,
      icon: Icons.event_note_outlined,
      actions: [
        if (isCurrentSemester)
          BracuSelectChip(
            icon: Icons.history_rounded,
            selected: _showDoneExams,
            compact: true,
            showArrow: false,
            showBorder: false,
            onTap: _toggleExamView,
          ),
        SemesterSessionSelector(
          selectedSemesterSessionId:
              _selectedSemesterSessionId ?? _currentSessionSemesterId,
          onSessionChanged: _onSemesterSessionChanged,
          iconOnly: true,
        ),
      ],
      body: FutureBuilder<_ExamScheduleData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError && _latestData == null) {
            return buildRefreshErrorState(
              onRefresh: _handleRefresh,
              error: snapshot.error,
            );
          }

          final examData = _latestData ?? snapshot.data;
          if (snapshot.connectionState == ConnectionState.waiting &&
              examData == null) {
            return buildRefreshLoadingState(onRefresh: _handleRefresh);
          }

          if (examData == null) {
            return buildRefreshEmptyState(
              onRefresh: _handleRefresh,
              message: 'No exam data available',
            );
          }

          if (examData.sections.isEmpty) {
            return buildRefreshEmptyState(
              onRefresh: _handleRefresh,
              message: 'No exam data available',
            );
          }

          final sections = examData.sections;
          final isPastSemester =
              _selectedSemesterSessionId != null &&
              _currentSessionSemesterId != null &&
              _selectedSemesterSessionId != _currentSessionSemesterId;
          final resolvedLists = _resolvedExamListsFor(
            examData,
            _showDoneExams,
            isPastSemester: isPastSemester,
          );
          final resolvedBySectionId = resolvedLists.resolvedBySectionId;
          final midExams = resolvedLists.midExams;
          final finalExams = resolvedLists.finalExams;
          ExamSectionResolved resolved(Section section) =>
              resolvedBySectionId[section.sectionId]!;
          String? midDate(Section section) => resolved(section).midDate;
          String? midStart(Section section) => resolved(section).midStartTime;
          String? midEnd(Section section) => resolved(section).midEndTime;
          String? midRoom(Section section) => resolved(section).midRoomNumber;
          String? finalDate(Section section) => resolved(section).finalDate;
          String? finalStart(Section section) =>
              resolved(section).finalStartTime;
          String? finalEnd(Section section) => resolved(section).finalEndTime;
          String? finalRoom(Section section) =>
              resolved(section).finalRoomNumber;
          final showPast = _showDoneExams;
          final now = DateTime.now();

          if (midExams.isEmpty && finalExams.isEmpty) {
            final hasAnyExamData = sections.any(
              (s) =>
                  midDate(s) != null ||
                  midStart(s) != null ||
                  finalDate(s) != null ||
                  finalStart(s) != null,
            );
            return buildRefreshEmptyState(
              onRefresh: _handleRefresh,
              message: showPast
                  ? 'No done exam available'
                  : (hasAnyExamData
                        ? 'No exam found'
                        : 'No exam data available'),
            );
          }

          final shouldHighlightCurrentSemester = !showPast;
          final today = DateTime(now.year, now.month, now.day);
          DateTime? nextExamTime;
          String? nextExamKey;
          if (shouldHighlightCurrentSemester) {
            for (final s in sections) {
              final midTime = BracuTime.parseDateTime(midDate(s), midStart(s));
              if (midTime != null &&
                  midTime.year == today.year &&
                  midTime.month == today.month &&
                  midTime.day == today.day &&
                  ExamVisibility.isUpcomingOrOngoingSchedule(
                    date: midDate(s),
                    start: midStart(s),
                    end: midEnd(s),
                    now: now,
                  )) {
                if (nextExamTime == null || midTime.isBefore(nextExamTime)) {
                  nextExamTime = midTime;
                  nextExamKey = '${s.sectionId}-mid';
                }
              }
              final finalTime = BracuTime.parseDateTime(
                finalDate(s),
                finalStart(s),
              );
              if (finalTime != null &&
                  finalTime.year == today.year &&
                  finalTime.month == today.month &&
                  finalTime.day == today.day &&
                  ExamVisibility.isUpcomingOrOngoingSchedule(
                    date: finalDate(s),
                    start: finalStart(s),
                    end: finalEnd(s),
                    now: now,
                  )) {
                if (nextExamTime == null || finalTime.isBefore(nextExamTime)) {
                  nextExamTime = finalTime;
                  nextExamKey = '${s.sectionId}-final';
                }
              }
            }
          }

          final highlightedKey = nextExamKey;

          final children = <Widget>[];
          final hasExamToday = sections.any((s) {
            final mDate = BracuTime.parseDate(midDate(s));
            final fDate = BracuTime.parseDate(finalDate(s));
            final hasMidToday =
                mDate != null &&
                mDate.year == today.year &&
                mDate.month == today.month &&
                mDate.day == today.day;
            final hasFinalToday =
                fDate != null &&
                fDate.year == today.year &&
                fDate.month == today.month &&
                fDate.day == today.day;
            return hasMidToday || hasFinalToday;
          });

          if (!showPast && !hasExamToday) {
            final todayWeekday = DateFormat('EEEE').format(now).toUpperCase();
            final todayDateLabel = formatLongDate(now);
            children.add(
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: BracuSectionTitle(
                            title:
                                'Today is ${formatWeekdayTitle(todayWeekday)}',
                          ),
                        ),
                        Text(
                          todayDateLabel,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: BracuPalette.textPrimary(context),
                          ),
                        ),
                      ],
                    ),
                    const Gap(12),
                    BracuCard(
                      child: Row(
                        children: [
                          const SectionBadge(
                            label: '--',
                            color: BracuPalette.primary,
                          ),
                          const Gap(12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'No Exam Today',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const Gap(4),
                                Text(
                                  'Enjoy your day off.',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: BracuPalette.textSecondary(context),
                                  ),
                                ),
                              ],
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

          _highlightScroll.clearHighlightKey();

          if (midExams.isNotEmpty) {
            children.addAll(
              midExams.map((section) {
                final isHighlighted =
                    highlightedKey == '${section.sectionId}-mid';
                if (isHighlighted) {
                  _highlightScroll.markHighlighted(true);
                }
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              BracuExamCard.formatExamDate(midDate(section)),
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: BracuPalette.textPrimary(context),
                              ),
                            ),
                          ),
                          Text(
                            'Midterm',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: BracuPalette.textPrimary(context),
                            ),
                          ),
                        ],
                      ),
                      const Gap(8),
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(18),
                          onTap: () {
                            final pdfUrl = resolved(section).midPdfUrl;
                            if (pdfUrl != null && pdfUrl.isNotEmpty) {
                              unawaited(openPdfUrl(context, pdfUrl));
                            }
                          },
                          child: RepaintBoundary(
                            child: BracuExamCard(
                              highlightKey: isHighlighted
                                  ? _highlightScroll.highlightKey
                                  : null,
                              isHighlighted: isHighlighted,
                              courseCode: section.courseCode,
                              sectionName: section.sectionName,
                              startTime: midStart(section),
                              endTime: midEnd(section),
                              roomNumber: midRoom(section),
                              faculties: section.faculties,
                              consumedSeat: section.consumedSeat,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            );
          }

          if (finalExams.isNotEmpty) {
            children.addAll(
              finalExams.map((section) {
                final isHighlighted =
                    highlightedKey == '${section.sectionId}-final';
                if (isHighlighted) {
                  _highlightScroll.markHighlighted(true);
                }
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              BracuExamCard.formatExamDate(finalDate(section)),
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: BracuPalette.textPrimary(context),
                              ),
                            ),
                          ),
                          Text(
                            'Final',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: BracuPalette.textPrimary(context),
                            ),
                          ),
                        ],
                      ),
                      const Gap(8),
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(18),
                          onTap: () {
                            final pdfUrl = resolved(section).finalPdfUrl;
                            if (pdfUrl != null && pdfUrl.isNotEmpty) {
                              unawaited(openPdfUrl(context, pdfUrl));
                            }
                          },
                          child: RepaintBoundary(
                            child: BracuExamCard(
                              highlightKey: isHighlighted
                                  ? _highlightScroll.highlightKey
                                  : null,
                              isHighlighted: isHighlighted,
                              courseCode: section.courseCode,
                              sectionName: section.sectionName,
                              startTime: finalStart(section),
                              endTime: finalEnd(section),
                              roomNumber: finalRoom(section),
                              faculties: section.faculties,
                              consumedSeat: section.consumedSeat,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            );
          }

          children.add(const Gap(8));
          unawaited(
            _highlightScroll.scrollToTarget(
              targetToken: highlightedKey,
              onRetryBuild: () {
                if (mounted) {
                  setState(() {});
                }
              },
            ),
          );

          return BracuRefreshList(
            onRefresh: _handleRefresh,
            controller: _scrollController,
            children: children,
          );
        },
      ),
    );
  }

  _ResolvedExamLists _resolvedExamListsFor(
    _ExamScheduleData examData,
    bool showPast, {
    bool isPastSemester = false,
  }) {
    final cached = _resolvedListsCache;
    if (cached != null &&
        identical(_resolvedForData, examData) &&
        _resolvedForShowDone == showPast &&
        _resolvedForIsPastSemester == isPastSemester) {
      return cached;
    }

    final sections = examData.sections;
    final overrides = examData.overrides;
    final examService = ExamScheduleService();
    final resolvedBySectionId = <int, ExamSectionResolved>{
      for (final section in sections)
        section.sectionId: examService.resolveSection(
          section: section,
          overrides: overrides,
        ),
    };
    ExamSectionResolved resolved(Section section) =>
        resolvedBySectionId[section.sectionId]!;
    String? midDate(Section section) => resolved(section).midDate;
    String? midStart(Section section) => resolved(section).midStartTime;
    String? midEnd(Section section) => resolved(section).midEndTime;
    String? finalDate(Section section) => resolved(section).finalDate;
    String? finalStart(Section section) => resolved(section).finalStartTime;
    String? finalEnd(Section section) => resolved(section).finalEndTime;

    final now = DateTime.now();
    bool isUpcoming(Section section, {required bool isMid}) {
      return ExamVisibility.isUpcomingOrOngoingSchedule(
        date: isMid ? midDate(section) : finalDate(section),
        start: isMid ? midStart(section) : finalStart(section),
        end: isMid ? midEnd(section) : finalEnd(section),
        now: now,
      );
    }

    bool hasExamValue(Section section, {required bool isMid}) {
      return isMid
          ? (midDate(section) != null || midStart(section) != null)
          : (finalDate(section) != null || finalStart(section) != null);
    }

    final allMidExams = sections
        .where((s) => hasExamValue(s, isMid: true))
        .toList();
    final allFinalExams = sections
        .where((s) => hasExamValue(s, isMid: false))
        .toList();

    final upcomingMidExams = sections
        .where(
          (s) => hasExamValue(s, isMid: true) && isUpcoming(s, isMid: true),
        )
        .toList();
    final upcomingFinalExams = sections
        .where(
          (s) => hasExamValue(s, isMid: false) && isUpcoming(s, isMid: false),
        )
        .toList();

    final pastMidExams = sections
        .where(
          (s) => hasExamValue(s, isMid: true) && !isUpcoming(s, isMid: true),
        )
        .toList();
    final pastFinalExams = sections
        .where(
          (s) => hasExamValue(s, isMid: false) && !isUpcoming(s, isMid: false),
        )
        .toList();

    var midExams = isPastSemester
        ? allMidExams
        : (showPast ? pastMidExams : upcomingMidExams);
    var finalExams = isPastSemester
        ? allFinalExams
        : (showPast ? pastFinalExams : upcomingFinalExams);

    if (!isPastSemester &&
        !showPast &&
        midExams.isEmpty &&
        finalExams.isEmpty &&
        (allMidExams.isNotEmpty || allFinalExams.isNotEmpty)) {
      midExams = allMidExams;
      finalExams = allFinalExams;
    }

    midExams.sort((a, b) {
      final aTime = BracuTime.parseDateTime(midDate(a), midStart(a));
      final bTime = BracuTime.parseDateTime(midDate(b), midStart(b));
      final cmp = ExamSorting.compareExamEntries(
        typeA: 'Midterm',
        typeB: 'Midterm',
        dateTimeA: aTime,
        dateTimeB: bTime,
        courseCodeA: a.courseCode,
        courseCodeB: b.courseCode,
        sectionNameA: a.sectionName,
        sectionNameB: b.sectionName,
      );
      return showPast ? -cmp : cmp;
    });

    finalExams.sort((a, b) {
      final aTime = BracuTime.parseDateTime(finalDate(a), finalStart(a));
      final bTime = BracuTime.parseDateTime(finalDate(b), finalStart(b));
      final cmp = ExamSorting.compareExamEntries(
        typeA: 'Final',
        typeB: 'Final',
        dateTimeA: aTime,
        dateTimeB: bTime,
        courseCodeA: a.courseCode,
        courseCodeB: b.courseCode,
        sectionNameA: a.sectionName,
        sectionNameB: b.sectionName,
      );
      return showPast ? -cmp : cmp;
    });

    final result = _ResolvedExamLists(
      resolvedBySectionId: resolvedBySectionId,
      midExams: midExams,
      finalExams: finalExams,
    );
    _resolvedForData = examData;
    _resolvedForShowDone = showPast;
    _resolvedListsCache = result;
    return result;
  }
}

class _ResolvedExamLists {
  const _ResolvedExamLists({
    required this.resolvedBySectionId,
    required this.midExams,
    required this.finalExams,
  });

  final Map<int, ExamSectionResolved> resolvedBySectionId;
  final List<Section> midExams;
  final List<Section> finalExams;
}

class _ExamScheduleData {
  const _ExamScheduleData({required this.sections, required this.overrides});

  final List<Section> sections;
  final Map<String, ExamScheduleOverride> overrides;
}
