import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:preconnect/api/exam_map_service.dart';
import 'package:preconnect/api/schedule_service.dart';
import 'package:preconnect/model/section_info.dart';
import 'package:preconnect/pages/shared_widgets/course_community_sheet.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/exam_sorting.dart';
import 'package:preconnect/tools/refresh_bus.dart';
import 'package:preconnect/tools/time_utils.dart';

class ExamSchedule extends StatefulWidget {
  const ExamSchedule({super.key});

  static final ValueNotifier<int> jumpSignal = ValueNotifier<int>(0);

  static void requestJump() {
    jumpSignal.value++;
  }

  @override
  State<ExamSchedule> createState() => _ExamScheduleState();
}

class _ExamScheduleState extends State<ExamSchedule> with RefreshBusState {
  late Future<_ExamScheduleData> _future;
  final ScrollController _scrollController = ScrollController();
  List<int> _semesterSessionOptions = const <int>[];
  int? _selectedSemesterSessionId;
  GlobalKey? _highlightKey;
  String? _lastHighlightKey;
  bool _didScroll = false;
  bool _scrollRetry = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadSemesterOptions());
    _future = _fetchExamData();
    ExamSchedule.jumpSignal.addListener(_onJumpRequested);
    bindRefreshBus(_onRefreshSignal);
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
    unawaited(_handleRefresh(notify: false));
  }

  void _onJumpRequested() {
    _didScroll = false;
    _scrollRetry = false;
    if (mounted) {
      setState(() {});
    }
  }

  Future<_ExamScheduleData> _fetchExamData({bool forceRefresh = false}) async {
    final service = ScheduleService();
    List<Section> sections;
    if (_selectedSemesterSessionId == null) {
      sections = await service.getStudentSections(forceRefresh: forceRefresh);
      return _buildExamDataFromSections(
        sections,
        forceRefresh: forceRefresh,
        forcedSemesterSessionId: null,
      );
    }
    if (forceRefresh) {
      await service.fetchStudentScheduleForSemester(
        semesterSessionId: _selectedSemesterSessionId,
      );
    }
    sections = service.parseStudentSections(
      await service.getStudentScheduleForSemester(
        semesterSessionId: _selectedSemesterSessionId,
        fromFetch: true,
      ),
    );
    return _buildExamDataFromSections(
      sections,
      forceRefresh: forceRefresh,
      forcedSemesterSessionId: _selectedSemesterSessionId,
    );
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

    final overrides = await ExamScheduleService().getOverridesForSections(
      sections,
      forceRefresh: forceRefresh,
      forcedSemesterSessionId: forcedSemesterSessionId,
    );
    return _ExamScheduleData(sections: sections, overrides: overrides);
  }

  bool _sameIntList(List<int> a, List<int> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Future<void> _loadSemesterOptions({
    int? baseSessionId,
    bool forceRefresh = false,
  }) async {
    final service = ScheduleService();
    final cached = await service.getCachedValidSemesterSessionIds();
    if (mounted &&
        cached.isNotEmpty &&
        !_sameIntList(_semesterSessionOptions, cached)) {
      setState(() {
        _semesterSessionOptions = cached;
      });
    }
    if (!forceRefresh && cached.isNotEmpty) return;
    final refreshed = await service.preloadValidSemesterSessionIds(
      baseSessionId: baseSessionId,
      forceRefresh: forceRefresh,
    );
    if (cached.isEmpty) {
      unawaited(
        service.preloadSemesterScheduleCache(
          semesterSessionIds: refreshed,
          forceRefresh: forceRefresh,
        ),
      );
    }
    if (!mounted || _sameIntList(_semesterSessionOptions, refreshed)) return;
    setState(() {
      _semesterSessionOptions = refreshed;
    });
  }

  String _semesterLabel(int? sessionId) {
    if (sessionId == null) return 'Current';
    return formatSemesterFromSessionIdInt(sessionId);
  }

  Future<void> _selectSemester(int? sessionId) async {
    if (_selectedSemesterSessionId == sessionId) return;
    setState(() {
      _selectedSemesterSessionId = sessionId;
      _didScroll = false;
      _scrollRetry = false;
      _future = _fetchExamData(forceRefresh: true);
    });
    await _future;
  }

  Widget _buildSemesterDropdownAction() {
    const currentMenuValue = -1;
    return BracuSelectDropdownChip<int>(
      label: _semesterLabel(_selectedSemesterSessionId),
      title: 'Select Semester',
      subtitle: 'Switch between current and archived exam schedules',
      selectedValue: _selectedSemesterSessionId ?? currentMenuValue,
      options: [
        const BracuSelectOption<int>(
          value: currentMenuValue,
          label: 'Current',
          icon: Icons.bolt_rounded,
          subtitle: 'Latest exam schedule',
        ),
        ..._semesterSessionOptions.map(
          (sessionId) => BracuSelectOption<int>(
            value: sessionId,
            label: _semesterLabel(sessionId),
            icon: Icons.history_rounded,
            subtitle: 'Archived semester',
          ),
        ),
      ],
      onSelected: (value) {
        if (!mounted) return;
        final sessionId = value == currentMenuValue ? null : value;
        unawaited(_selectSemester(sessionId));
      },
    );
  }

  Future<void> _handleRefresh({bool notify = true}) async {
    if (!await ensureOnline(context, notify: notify)) {
      return;
    }
    final service = ScheduleService();
    String? currentScheduleJson;
    if (_selectedSemesterSessionId == null) {
      currentScheduleJson = await service.fetchStudentSchedule();
      final refreshed = await service.refreshArchiveSemesterCacheIfNeeded(
        currentScheduleJson: currentScheduleJson,
      );
      if (mounted && !_sameIntList(_semesterSessionOptions, refreshed)) {
        setState(() {
          _semesterSessionOptions = refreshed;
        });
      }
    }
    setState(() {
      _didScroll = false;
      _scrollRetry = false;
      _future = _selectedSemesterSessionId == null
          ? _buildExamDataFromSections(
              service.parseStudentSections(currentScheduleJson),
              forceRefresh: true,
              forcedSemesterSessionId: null,
            )
          : _fetchExamData(forceRefresh: true);
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
    return DateFormat('d MMMM, yyyy').format(dt);
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
        : _semesterLabel(_selectedSemesterSessionId);
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
      actions: [_buildSemesterDropdownAction()],
      body: FutureBuilder<_ExamScheduleData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return buildRefreshLoadingState(
              onRefresh: _handleRefresh,
              label: 'Loading...',
            );
          } else if (snapshot.hasError) {
            return buildRefreshErrorState(
              onRefresh: _handleRefresh,
              error: snapshot.error,
            );
          } else if (!snapshot.hasData || snapshot.data!.sections.isEmpty) {
            return buildRefreshEmptyState(
              onRefresh: _handleRefresh,
              message: 'No exam data available',
            );
          }

          final examData = snapshot.data!;
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

          final midExams = sections
              .where(
                (s) =>
                    midDate(s) != null ||
                    midStart(s) != null ||
                    midEnd(s) != null,
              )
              .toList();
          final finalExams = sections
              .where(
                (s) =>
                    finalDate(s) != null ||
                    finalStart(s) != null ||
                    finalEnd(s) != null,
              )
              .toList();

          midExams.sort((a, b) {
            final aTime = BracuTime.parseDateTime(midDate(a), midStart(a));
            final bTime = BracuTime.parseDateTime(midDate(b), midStart(b));
            return ExamSorting.compareExamEntries(
              typeA: 'Midterm',
              typeB: 'Midterm',
              dateTimeA: aTime,
              dateTimeB: bTime,
              courseCodeA: a.courseCode,
              courseCodeB: b.courseCode,
              sectionNameA: a.sectionName,
              sectionNameB: b.sectionName,
            );
          });

          finalExams.sort((a, b) {
            final aTime = BracuTime.parseDateTime(finalDate(a), finalStart(a));
            final bTime = BracuTime.parseDateTime(finalDate(b), finalStart(b));
            return ExamSorting.compareExamEntries(
              typeA: 'Final',
              typeB: 'Final',
              dateTimeA: aTime,
              dateTimeB: bTime,
              courseCodeA: a.courseCode,
              courseCodeB: b.courseCode,
              sectionNameA: a.sectionName,
              sectionNameB: b.sectionName,
            );
          });

          if (midExams.isEmpty && finalExams.isEmpty) {
            return buildRefreshEmptyState(
              onRefresh: _handleRefresh,
              message: 'Exam schedule not published yet',
            );
          }

          final now = DateTime.now();
          final shouldHighlightCurrentSemester =
              _selectedSemesterSessionId == null;
          DateTime? nextExamTime;
          String? nextExamKey;
          DateTime? ongoingExamEnd;
          String? ongoingExamKey;
          if (shouldHighlightCurrentSemester) {
            for (final s in sections) {
              final midTime = BracuTime.parseDateTime(midDate(s), midStart(s));
              final midEndTime = BracuTime.parseDateTime(midDate(s), midEnd(s));
              if (midTime != null) {
                if (midEndTime != null &&
                    now.isAfter(midTime) &&
                    now.isBefore(midEndTime)) {
                  if (ongoingExamEnd == null ||
                      midEndTime.isBefore(ongoingExamEnd)) {
                    ongoingExamEnd = midEndTime;
                    ongoingExamKey = '${s.sectionId}-mid';
                  }
                } else if (midTime.isAfter(now)) {
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
              final finalEndTime = BracuTime.parseDateTime(
                finalDate(s),
                finalEnd(s),
              );
              if (finalTime != null) {
                if (finalEndTime != null &&
                    now.isAfter(finalTime) &&
                    now.isBefore(finalEndTime)) {
                  if (ongoingExamEnd == null ||
                      finalEndTime.isBefore(ongoingExamEnd)) {
                    ongoingExamEnd = finalEndTime;
                    ongoingExamKey = '${s.sectionId}-final';
                  }
                } else if (finalTime.isAfter(now)) {
                  if (nextExamTime == null ||
                      finalTime.isBefore(nextExamTime)) {
                    nextExamTime = finalTime;
                    nextExamKey = '${s.sectionId}-final';
                  }
                }
              }
            }
          }

          final highlightedKey = shouldHighlightCurrentSemester
              ? ongoingExamKey ?? nextExamKey
              : null;

          final children = <Widget>[];
          _highlightKey = null;

          if (midExams.isNotEmpty) {
            children.addAll(
              midExams.map((section) {
                final isHighlighted =
                    highlightedKey == '${section.sectionId}-mid';
                if (isHighlighted) {
                  _highlightKey ??= GlobalKey();
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
                            key: isHighlighted ? _highlightKey : null,
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
            if (finalExams.isNotEmpty) {
              children.add(
                Padding(
                  padding: const EdgeInsets.only(top: 2, bottom: 12),
                  child: Divider(
                    height: 1,
                    thickness: 1,
                    color: BracuPalette.accent.withValues(alpha: 0.45),
                  ),
                ),
              );
            } else {
              children.add(const SizedBox(height: 6));
            }
          }

          if (finalExams.isNotEmpty) {
            children.addAll(
              finalExams.map((section) {
                final isHighlighted =
                    highlightedKey == '${section.sectionId}-final';
                if (isHighlighted) {
                  _highlightKey ??= GlobalKey();
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
                            key: isHighlighted ? _highlightKey : null,
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

          if (highlightedKey != null && highlightedKey != _lastHighlightKey) {
            _lastHighlightKey = highlightedKey;
            _didScroll = false;
            _scrollRetry = false;
          }
          if (!_didScroll && _highlightKey != null) {
            attemptScrollToHighlightedKey(
              highlightKey: _highlightKey,
              hasRetried: _scrollRetry,
              retry: () {
                _scrollRetry = true;
                if (mounted) {
                  setState(() {});
                }
              },
              onScrolled: () {
                _didScroll = true;
              },
              alignment: 0.18,
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

class _ExamScheduleData {
  const _ExamScheduleData({required this.sections, required this.overrides});

  final List<Section> sections;
  final Map<String, ExamScheduleOverride> overrides;
}
