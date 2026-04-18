import 'dart:async';
import 'package:flutter/material.dart';
import 'package:preconnect/api/schedule_service.dart';
import 'package:preconnect/model/section_info.dart' as section;
import 'package:preconnect/pages/shared_widgets/course_community_sheet.dart';
import 'package:preconnect/pages/shared_widgets/schedule_entry_card.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/refresh_bus.dart';
import 'package:preconnect/tools/ramadan_timing.dart';
import 'package:preconnect/tools/time_utils.dart';

class ClassSchedule extends StatefulWidget {
  const ClassSchedule({super.key});

  static final ValueNotifier<int> jumpSignal = ValueNotifier<int>(0);

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

  late Future<_ScheduleData> _future;
  final ScrollController _scrollController = ScrollController();
  List<int> _semesterSessionOptions = const <int>[];
  int? _selectedSemesterSessionId;
  GlobalKey? _highlightKey;
  String? _lastHighlightToken;
  bool _didScroll = false;
  bool _scrollRetry = false;
  int _visibleWeekCount = _initialVisibleWeekCount;

  @override
  void initState() {
    super.initState();
    unawaited(_loadSemesterOptions());
    _future = _loadSchedule();
    ClassSchedule.jumpSignal.addListener(_onJumpRequested);
    bindRefreshBus(_onRefreshSignal);
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
    unawaited(_handleRefresh(notify: false));
  }

  void _onJumpRequested() {
    _didScroll = false;
    _scrollRetry = false;
    if (mounted) {
      setState(() {
        _visibleWeekCount = _initialVisibleWeekCount;
      });
    }
  }

  void _attemptScrollToHighlight() {
    attemptScrollToHighlightedKey(
      highlightKey: _highlightKey,
      hasRetried: _scrollRetry,
      retry: () {
        _scrollRetry = true;
        _attemptScrollToHighlight();
      },
      onScrolled: () {
        _didScroll = true;
      },
      alignment: 0.18,
    );
  }

  Future<_ScheduleData> _loadSchedule({bool forceRefresh = false}) async {
    final shouldHighlightCurrentSemester = _selectedSemesterSessionId == null;
    final ramadanFuture = RamadanTiming.isRamadan(forceRefresh: forceRefresh);
    final service = ScheduleService();
    final sections = shouldHighlightCurrentSemester
        ? await service.getStudentSections(
            semesterSessionId: null,
            forceRefresh: forceRefresh,
          )
        : service.parseStudentSections(
            await service.getStudentScheduleForSemester(
              semesterSessionId: _selectedSemesterSessionId,
              fromFetch: true,
            ),
          );
    final isRamadan = await ramadanFuture;
    return _buildScheduleDataFromSections(
      sections,
      shouldHighlightCurrentSemester: shouldHighlightCurrentSemester,
      isRamadan: isRamadan,
    );
  }

  _ScheduleData _buildScheduleDataFromSections(
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

    if (sections.isNotEmpty) {
      final sessionIds = sections.map((s) => s.semesterSessionId).toList()
        ..sort((a, b) => b.compareTo(a));
      final baseSessionId = sessionIds.first;
      if (!_semesterSessionOptions.contains(baseSessionId) && mounted) {
        setState(() {
          _semesterSessionOptions = [baseSessionId, ..._semesterSessionOptions];
        });
      }
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
          "schedule": classSchedule,
          "courseCode": section.courseCode,
          "sectionName": section.sectionName,
          "roomNumber": section.roomNumber,
          "faculties": section.faculties,
          "consumedSeat": section.consumedSeat,
          "capacity": section.capacity,
          "courseType": section.courseType,
          "semesterSessionId": section.semesterSessionId,
        });

        if (shouldHighlightCurrentSemester) {
          final candidate = _nextOccurrence(
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
        final aSchedule = a["schedule"] as section.ClassSchedule;
        final bSchedule = b["schedule"] as section.ClassSchedule;
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
    if (!mounted) return;
    if (_sameIntList(_semesterSessionOptions, refreshed)) return;
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
      _visibleWeekCount = _initialVisibleWeekCount;
      _future = _loadSchedule(forceRefresh: true);
    });
    await _future;
  }

  Widget _buildSemesterDropdownAction() {
    const currentMenuValue = -1;
    return BracuSelectDropdownChip<int>(
      label: _semesterLabel(_selectedSemesterSessionId),
      title: 'Select Semester',
      subtitle: 'Switch between current and archived class schedules',
      selectedValue: _selectedSemesterSessionId ?? currentMenuValue,
      options: [
        const BracuSelectOption<int>(
          value: currentMenuValue,
          label: 'Current',
          icon: Icons.bolt_rounded,
          subtitle: 'Latest class schedule',
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
      _visibleWeekCount = _initialVisibleWeekCount;
      _future = _selectedSemesterSessionId == null
          ? _loadScheduleFromJson(currentScheduleJson)
          : _loadSchedule(forceRefresh: true);
    });
    await _future;
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

  Future<_ScheduleData> _loadScheduleFromJson(String? scheduleJson) async {
    final shouldHighlightCurrentSemester = _selectedSemesterSessionId == null;
    final ramadanFuture = RamadanTiming.isRamadan(forceRefresh: true);
    final sections = ScheduleService().parseStudentSections(scheduleJson);
    final isRamadan = await ramadanFuture;
    return _buildScheduleDataFromSections(
      sections,
      shouldHighlightCurrentSemester: shouldHighlightCurrentSemester,
      isRamadan: isRamadan,
    );
  }

  DateTime? _nextOccurrence({
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
      actions: [_buildSemesterDropdownAction()],
      body: FutureBuilder<_ScheduleData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return BracuRefreshScroll(
              onRefresh: _handleRefresh,
              showScrollTopButton: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    _ClassScheduleLoadingHeader(),
                    SizedBox(height: 12),
                    BracuLoading(itemCount: 4),
                    SizedBox(height: 12),
                    BracuLoading(itemCount: 3),
                    SizedBox(height: 12),
                    BracuLoading(itemCount: 4),
                  ],
                ),
              ),
            );
          }
          if (snapshot.hasError) {
            return buildRefreshErrorState(
              onRefresh: _handleRefresh,
              error: snapshot.error,
            );
          }

          final grouped = snapshot.data?.grouped ?? {};
          final scrollSchedule = snapshot.data?.scrollSchedule;
          final scrollDateTime = snapshot.data?.scrollDateTime;
          final shouldHighlightCurrentSemester =
              _selectedSemesterSessionId == null;
          final isRamadan = snapshot.data?.isRamadan ?? false;
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
          _highlightKey = null;
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
                      _highlightKey ??= GlobalKey();
                    }
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: ScheduleEntryCard(
                        key: isScrollTarget ? _highlightKey : null,
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
                              ? _semesterLabel(_selectedSemesterSessionId)
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
                  child: OutlinedButton(
                    onPressed: () {
                      setState(() {
                        _visibleWeekCount += 1;
                      });
                    },
                    child: const Text('Next week'),
                  ),
                ),
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

class _ClassScheduleLoadingHeader extends StatelessWidget {
  const _ClassScheduleLoadingHeader();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BracuLoading(itemCount: 1, compact: true),
        SizedBox(height: 12),
        BracuLoading(itemCount: 2, compact: true),
      ],
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
