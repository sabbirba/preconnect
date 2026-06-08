import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:preconnect/api/exam_map.dart';
import 'package:preconnect/api/schedule.dart';
import 'package:preconnect/model/section_info.dart';
import 'package:preconnect/pages/shared_widgets/highlight_scroll_helper.dart';
import 'package:preconnect/pages/shared_widgets/course_community_sheet.dart';
import 'package:preconnect/pages/shared_widgets/current_session_helper.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/exam_sorting.dart';
import 'package:preconnect/tools/exam_visibility.dart';
import 'package:preconnect/tools/json_snapshot_store.dart';
import 'package:preconnect/tools/preload_cache.dart';
import 'package:preconnect/tools/refresh_bus.dart';
import 'package:preconnect/tools/time_utils.dart';

class ExamSchedule extends StatefulWidget {
  const ExamSchedule({super.key});

  static final ValueNotifier<int> jumpSignal = ValueNotifier<int>(0);

  static Future<void> preload() async {
    await _ExamScheduleState.preloadData();
  }

  static void requestJump() {
    jumpSignal.value++;
  }

  @override
  State<ExamSchedule> createState() => _ExamScheduleState();
}

class _ExamScheduleState extends State<ExamSchedule> with RefreshBusState {
  static final PreloadCache<_ExamScheduleData> cache =
      PreloadCache<_ExamScheduleData>();

  late Future<_ExamScheduleData> _future;
  _ExamScheduleData? _latestData;
  final ScrollController _scrollController = ScrollController();
  late final HighlightScrollCoordinator _highlightScroll =
      HighlightScrollCoordinator(scrollController: _scrollController);
  int? _currentSessionSemesterId;
  bool _showUpcomingExams = true;

  @override
  void initState() {
    super.initState();
    _latestData = cache.value;
    _future = cache.value == null
        ? _initializeExamSchedule()
        : Future<_ExamScheduleData>.value(cache.value!);
    unawaited(_loadCurrentSessionSemesterId());
    unawaited(_warmAndBind());
    ExamSchedule.jumpSignal.addListener(_onJumpRequested);
    bindRefreshBus(_onRefreshSignal);
  }

  Future<void> _warmAndBind() async {
    final data = await preloadData();
    if (!mounted) return;
    setState(() {
      _latestData = data;
      _future = Future<_ExamScheduleData>.value(data);
    });
  }

  static Future<_ExamScheduleData> preloadData({
    bool forceRefresh = false,
  }) async {
    return cache.load(
      forceRefresh: forceRefresh,
      fetch: () => _loadExamData(forceRefresh: forceRefresh),
    );
  }

  static Future<_ExamScheduleData> _loadExamData({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh) {
      final cachedSections = await JsonSnapshotStore.readSections();
      if (cachedSections != null && cachedSections.isNotEmpty) {
        final overrides = await ExamScheduleService().getOverridesForSections(
          cachedSections,
          forceRefresh: false,
        );
        return _ExamScheduleData(
          sections: cachedSections,
          overrides: overrides,
        );
      }
    }

    final currentSessionSemesterId =
        await resolveCurrentSessionSemesterIdWithRetry();
    if (currentSessionSemesterId == null) {
      final cachedSections = await JsonSnapshotStore.readSections();
      if (cachedSections != null && cachedSections.isNotEmpty) {
        final overrides = await ExamScheduleService().getOverridesForSections(
          cachedSections,
          forceRefresh: false,
        );
        return _ExamScheduleData(
          sections: cachedSections,
          overrides: overrides,
        );
      }

      return const _ExamScheduleData(
        sections: <Section>[],
        overrides: <String, ExamScheduleOverride>{},
      );
    }
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
    final sections = service.parseStudentSections(
      jsonString,
      semesterSessionId: currentSessionSemesterId,
    );

    if (sections.isEmpty) {
      final cachedSections = await JsonSnapshotStore.readSections();
      if (cachedSections != null && cachedSections.isNotEmpty) {
        final overrides = await ExamScheduleService().getOverridesForSections(
          cachedSections,
          forceRefresh: false,
        );
        return _ExamScheduleData(
          sections: cachedSections,
          overrides: overrides,
        );
      }

      return const _ExamScheduleData(
        sections: <Section>[],
        overrides: <String, ExamScheduleOverride>{},
      );
    }

    unawaited(JsonSnapshotStore.updateSections(sections));
    final examService = ExamScheduleService();
    final overrides = await examService.getOverridesForSections(
      sections,
      forceRefresh: true,
      forcedSemesterSessionId: currentSessionSemesterId,
    );
    final data = _ExamScheduleData(sections: sections, overrides: overrides);
    return data;
  }

  Future<_ExamScheduleData> _initializeExamSchedule() async {
    await _loadCurrentSessionSemesterId();
    return _fetchExamData();
  }

  @override
  void dispose() {
    ExamSchedule.jumpSignal.removeListener(_onJumpRequested);
    _scrollController.dispose();
    unbindRefreshBus(_onRefreshSignal);
    super.dispose();
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
    if (mounted) {
      setState(() {});
    }
  }

  void _toggleExamView() {
    setState(() {
      _showUpcomingExams = !_showUpcomingExams;
      _highlightScroll.resetScrollState();
    });
  }

  Future<_ExamScheduleData> _fetchExamData({bool forceRefresh = false}) async {
    if (!forceRefresh) {
      final cachedSections = await JsonSnapshotStore.readSections();
      if (cachedSections != null && cachedSections.isNotEmpty) {
        final overrides = await ExamScheduleService().getOverridesForSections(
          cachedSections,
          forceRefresh: false,
        );
        final data = _ExamScheduleData(sections: cachedSections, overrides: overrides);
        cache.value = data;
        if (mounted) {
          setState(() {
            _latestData = data;
          });
        }
        return data;
      }
    }

    final service = ScheduleService();
    final currentSessionSemesterId =
        _currentSessionSemesterId ??
        await resolveCurrentSessionSemesterIdWithRetry();
    if (currentSessionSemesterId == null) {
      final cachedSections = await JsonSnapshotStore.readSections();
      if (cachedSections != null && cachedSections.isNotEmpty) {
        final overrides = await ExamScheduleService().getOverridesForSections(
          cachedSections,
          forceRefresh: false,
        );
        final data = _ExamScheduleData(sections: cachedSections, overrides: overrides);
        cache.value = data;
        if (mounted) {
          setState(() {
            _latestData = data;
          });
        }
        return data;
      }

      return const _ExamScheduleData(
        sections: <Section>[],
        overrides: <String, ExamScheduleOverride>{},
      );
    }
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
    final parsedSections = service.parseStudentSections(
      jsonString,
      semesterSessionId: currentSessionSemesterId,
    );

    if (parsedSections.isNotEmpty) {
      unawaited(JsonSnapshotStore.updateSections(parsedSections));
    }

    final data = await _buildExamDataFromSections(
      parsedSections,
      forceRefresh: forceRefresh,
      forcedSemesterSessionId: currentSessionSemesterId,
    );
    cache.value = data;
    if (mounted) {
      setState(() {
        _latestData = data;
      });
    }
    return data;
  }

  Future<_ExamScheduleData> _buildExamDataFromSections(
    List<Section> sections, {
    required bool forceRefresh,
    int? forcedSemesterSessionId,
  }) async {
    if (sections.isEmpty) {
      return const _ExamScheduleData(
        sections: <Section>[],
        overrides: <String, ExamScheduleOverride>{},
      );
    }

    final examService = ExamScheduleService();
    final overrides = await examService.getOverridesForSections(
      sections,
      forceRefresh: true,
      forcedSemesterSessionId: forcedSemesterSessionId,
    );
    return _ExamScheduleData(sections: sections, overrides: overrides);
  }

  Future<void> _loadCurrentSessionSemesterId() async {
    final currentSessionSemesterId =
        await resolveCurrentSessionSemesterIdWithRetry();
    if (!mounted || currentSessionSemesterId == null) return;
    if (_currentSessionSemesterId == currentSessionSemesterId) return;
    setState(() {
      _currentSessionSemesterId = currentSessionSemesterId;
    });
    unawaited(_handleRefresh(notify: false));
  }

  Future<void> _handleRefresh({bool notify = true}) async {
    if (!await ensureOnline(context, notify: notify)) {
      return;
    }
    if (!mounted) return;
    setState(() {
      _future = preloadData(forceRefresh: true);
    });
    await _future;
    if (notify) {
      RefreshBus.instance.notify(reason: 'exam_schedule');
    }
  }

  String _formatExamDateLabel(String? input) {
    if (input == null || input.trim().isEmpty) return 'Not published yet';
    final raw = input.trim();
    final dt = BracuTime.parseDate(raw) ?? DateTime.tryParse(raw);
    if (dt == null) return raw;
    return DateFormat('EEEE, d MMMM, yyyy').format(dt);
  }

  String _formatExamTimeLabel(String? start, String? end) {
    final value = formatTimeRange(start, end).trim();
    if (value.isEmpty) return 'Not published yet';
    return value;
  }

  String _formatExamRoomLabel(String? room) {
    final value = (room ?? '').trim();
    if (value.isEmpty) return 'TBA';
    return value;
  }

  Future<void> _openExamActionsSheet({
    required Section section,
    required String examType,
    required String examDateLabel,
    required String examTimeLabel,
    required String roomLabel,
  }) async {
    final semesterLabel = section.semesterSessionId > 0
        ? formatSemesterFromSessionIdInt(section.semesterSessionId)
        : 'Current';
    await showBracuBottomSheet<void>(
      context,
      title: section.courseCode,
      initialChildSize: 0.88,
      builder: (sheetContext, textPrimary, textSecondary) {
        return CourseCommunitySheet.forExam(
          courseCode: section.courseCode,
          sectionName: section.sectionName,
          semesterLabel: semesterLabel,
          roomNumber: roomLabel,
          faculties: section.faculties,
          consumedSeat: section.consumedSeat,
          courseType: section.courseType,
          examType: examType,
          examDateLabel: examDateLabel,
          examTimeLabel: examTimeLabel,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return BracuPageScaffold(
      title: 'Exams',
      subtitle: 'Mid & Final',
      icon: Icons.event_note_outlined,
      actions: [
        BracuSelectChip(
          label: 'Done',
          icon: Icons.history_rounded,
          selected: !_showUpcomingExams,
          compact: true,
          showArrow: false,
          onTap: _toggleExamView,
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
          String? midRoom(Section section) => resolved(section).midRoomNumber;
          String? finalDate(Section section) => resolved(section).finalDate;
          String? finalStart(Section section) =>
              resolved(section).finalStartTime;
          String? finalEnd(Section section) => resolved(section).finalEndTime;
          String? finalRoom(Section section) =>
              resolved(section).finalRoomNumber;

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

          final upcomingMidExams = sections
              .where(
                (s) =>
                    hasExamValue(s, isMid: true) && isUpcoming(s, isMid: true),
              )
              .toList();
          final upcomingFinalExams = sections
              .where(
                (s) =>
                    hasExamValue(s, isMid: false) &&
                    isUpcoming(s, isMid: false),
              )
              .toList();

          final pastMidExams = sections
              .where(
                (s) =>
                    hasExamValue(s, isMid: true) && !isUpcoming(s, isMid: true),
              )
              .toList();
          final pastFinalExams = sections
              .where(
                (s) =>
                    hasExamValue(s, isMid: false) &&
                    !isUpcoming(s, isMid: false),
              )
              .toList();

          final showPast = !_showUpcomingExams;

          final midExams = showPast ? pastMidExams : upcomingMidExams;
          final finalExams = showPast ? pastFinalExams : upcomingFinalExams;

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
              message: hasAnyExamData
                  ? 'No exams found'
                  : 'No exam data available',
            );
          }

          final shouldHighlightCurrentSemester = !showPast;
          DateTime? nextExamTime;
          String? nextExamKey;
          if (shouldHighlightCurrentSemester) {
            for (final s in sections) {
              final midTime = BracuTime.parseDateTime(midDate(s), midStart(s));
              if (midTime != null &&
                  ExamVisibility.isUpcomingOrOngoingSchedule(
                    date: midDate(s),
                    start: midStart(s),
                    end: midEnd(s),
                    now: now,
                  )) {
                if (midTime.isAfter(now)) {
                  if (nextExamTime == null || midTime.isBefore(nextExamTime)) {
                    nextExamTime = midTime;
                    nextExamKey = '${s.sectionId}-mid';
                  }
                }
              }
              final finalTime = BracuTime.parseDateTime(
                finalDate(s),
                finalStart(s),
              );
              if (finalTime != null &&
                  ExamVisibility.isUpcomingOrOngoingSchedule(
                    date: finalDate(s),
                    start: finalStart(s),
                    end: finalEnd(s),
                    now: now,
                  )) {
                if (finalTime.isAfter(now)) {
                  if (nextExamTime == null ||
                      finalTime.isBefore(nextExamTime)) {
                    nextExamTime = finalTime;
                    nextExamKey = '${s.sectionId}-final';
                  }
                }
              }
            }
          }

          final highlightedKey = nextExamKey;

          final children = <Widget>[];
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
                              _formatExamDateLabel(midDate(section)),
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
                      const SizedBox(height: 8),
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(18),
                          onTap: () {
                            _openExamActionsSheet(
                              section: section,
                              examType: 'Midterm',
                              examDateLabel: _formatExamDateLabel(
                                midDate(section),
                              ),
                              examTimeLabel: _formatExamTimeLabel(
                                midStart(section),
                                midEnd(section),
                              ),
                              roomLabel: _formatExamRoomLabel(midRoom(section)),
                            );
                          },
                          child: BracuCard(
                            key: isHighlighted
                                ? _highlightScroll.highlightKey
                                : null,
                            isHighlighted: isHighlighted,
                            highlightColor: BracuPalette.primary,
                            child: Row(
                              children: [
                                SectionBadge(
                                  label: formatSectionBadge(
                                    section.sectionName,
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
                                        section.courseCode,
                                        style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        _formatExamTimeLabel(
                                          midStart(section),
                                          midEnd(section),
                                        ),
                                        style: TextStyle(
                                          color: BracuPalette.textPrimary(
                                            context,
                                          ),
                                          fontWeight: FontWeight.w700,
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
                                        _formatExamRoomLabel(midRoom(section)),
                                        textAlign: TextAlign.right,
                                        style: TextStyle(
                                          color: BracuPalette.textPrimary(
                                            context,
                                          ),
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      if (section.faculties.trim().isNotEmpty ||
                                          section.consumedSeat > 0) ...[
                                        const SizedBox(height: 2),
                                        Text.rich(
                                          TextSpan(
                                            children: [
                                              if (section.faculties
                                                  .trim()
                                                  .isNotEmpty)
                                                TextSpan(
                                                  text: section.faculties
                                                      .trim(),
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w700,
                                                    color:
                                                        BracuPalette.textPrimary(
                                                          context,
                                                        ),
                                                  ),
                                                ),
                                              if (section.consumedSeat > 0)
                                                TextSpan(
                                                  text:
                                                      '${section.faculties.trim().isEmpty ? '' : ' '}(${section.consumedSeat})',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color:
                                                        BracuPalette.textSecondary(
                                                          context,
                                                        ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                          textAlign: TextAlign.right,
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
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
                              _formatExamDateLabel(finalDate(section)),
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
                      const SizedBox(height: 8),
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(18),
                          onTap: () {
                            _openExamActionsSheet(
                              section: section,
                              examType: 'Final',
                              examDateLabel: _formatExamDateLabel(
                                finalDate(section),
                              ),
                              examTimeLabel: _formatExamTimeLabel(
                                finalStart(section),
                                finalEnd(section),
                              ),
                              roomLabel: _formatExamRoomLabel(
                                finalRoom(section),
                              ),
                            );
                          },
                          child: BracuCard(
                            key: isHighlighted
                                ? _highlightScroll.highlightKey
                                : null,
                            isHighlighted: isHighlighted,
                            highlightColor: BracuPalette.primary,
                            child: Row(
                              children: [
                                SectionBadge(
                                  label: formatSectionBadge(
                                    section.sectionName,
                                  ),
                                  color: BracuPalette.accent,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  flex: 7,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        section.courseCode,
                                        style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        _formatExamTimeLabel(
                                          finalStart(section),
                                          finalEnd(section),
                                        ),
                                        style: TextStyle(
                                          color: BracuPalette.textPrimary(
                                            context,
                                          ),
                                          fontWeight: FontWeight.w700,
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
                                        _formatExamRoomLabel(
                                          finalRoom(section),
                                        ),
                                        textAlign: TextAlign.right,
                                        style: TextStyle(
                                          color: BracuPalette.textPrimary(
                                            context,
                                          ),
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      if (section.faculties.trim().isNotEmpty ||
                                          section.consumedSeat > 0) ...[
                                        const SizedBox(height: 2),
                                        Text.rich(
                                          TextSpan(
                                            children: [
                                              if (section.faculties
                                                  .trim()
                                                  .isNotEmpty)
                                                TextSpan(
                                                  text: section.faculties
                                                      .trim(),
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w700,
                                                    color:
                                                        BracuPalette.textPrimary(
                                                          context,
                                                        ),
                                                  ),
                                                ),
                                              if (section.consumedSeat > 0)
                                                TextSpan(
                                                  text:
                                                      '${section.faculties.trim().isEmpty ? '' : ' '}(${section.consumedSeat})',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color:
                                                        BracuPalette.textSecondary(
                                                          context,
                                                        ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                          textAlign: TextAlign.right,
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
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

          children.add(const SizedBox(height: 8));
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
}

class _ExamScheduleData {
  const _ExamScheduleData({required this.sections, required this.overrides});

  final List<Section> sections;
  final Map<String, ExamScheduleOverride> overrides;
}
