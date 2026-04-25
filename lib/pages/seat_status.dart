import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:preconnect/api/seat_status_service.dart';
import 'package:preconnect/pages/home_tab.dart';
import 'package:preconnect/model/section_info.dart' as section;
import 'package:preconnect/pages/notifications.dart';
import 'package:preconnect/pages/shared_widgets/course_community_sheet.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/ramadan_timing.dart';
import 'package:preconnect/tools/token_storage.dart';
import 'package:preconnect/tools/time_utils.dart';
part 'shared_widgets/seat_status_methods.dart';

class SeatStatusPage extends StatefulWidget {
  const SeatStatusPage({super.key});
  @override
  State<SeatStatusPage> createState() => _SeatStatusPageState();
}

class _SeatStatusPageState extends State<SeatStatusPage>
    with WidgetsBindingObserver {
  static const String _pinScope = 'seat_status';
  static const List<String> _weekdayOrder = <String>[
    'SUNDAY',
    'MONDAY',
    'TUESDAY',
    'WEDNESDAY',
    'THURSDAY',
    'FRIDAY',
    'SATURDAY',
  ];

  final SeatStatusService _service = SeatStatusService();
  final List<_SeatStatusCardData> _cards = <_SeatStatusCardData>[];
  final List<_SeatStatusCardData> _visibleCards = <_SeatStatusCardData>[];
  final Set<String> _pinnedSections = <String>{};
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  Timer? _pollTimer;
  bool _pollInFlight = false;
  bool _isInitialLoading = true;
  String _searchQuery = '';
  bool _isDetailsRefreshing = false;
  bool _availableOnly = false;
  String _selectedDayFilter = '';
  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      _searchDebounce?.cancel();
      _searchDebounce = Timer(const Duration(milliseconds: 150), () {
        if (!mounted) return;
        final next = _searchController.text.trim().toLowerCase();
        _updateSearchQuery(next);
      });
    });
    unawaited(_loadPins());
    unawaited(_reloadAll());
    WidgetsBinding.instance.addObserver(this);
    HomeTabRegistry.activeTab.addListener(_onActiveTabChanged);
    _updatePollingStrategy();
  }

  @override
  void dispose() {
    _stopPolling();
    WidgetsBinding.instance.removeObserver(this);
    HomeTabRegistry.activeTab.removeListener(_onActiveTabChanged);
    _searchDebounce?.cancel();
    _pollTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _updatePollingStrategy();
  }

  void _onActiveTabChanged() {
    if (!mounted) return;
    _updatePollingStrategy();
  }

  Future<void> _loadPins() async {
    final pins = await CoursePinStore.load(_pinScope);
    if (!mounted) return;
    setState(() {
      _pinnedSections
        ..clear()
        ..addAll(pins);
    });
    if (_cards.isNotEmpty) {
      final refreshed = List<_SeatStatusCardData>.from(_cards);
      _sortCardsByCourseAndSection(refreshed);
      _applyCardsSnapshot(refreshed, isInitialLoading: false);
    }
  }

  Future<void> _togglePin(int sectionId) async {
    final key = sectionId.toString();
    final willPin = !_pinnedSections.contains(key);
    setState(() {
      if (willPin) {
        _pinnedSections.add(key);
      } else {
        _pinnedSections.remove(key);
      }
    });
    await CoursePinStore.save(_pinScope, _pinnedSections);
    if (!mounted) return;
    final refreshed = List<_SeatStatusCardData>.from(_cards);
    _sortCardsByCourseAndSection(refreshed);
    _applyCardsSnapshot(refreshed, isInitialLoading: false);
    showAppSnackBar(
      context,
      willPin ? 'Section pinned to top' : 'Section unpinned',
    );
  }

  Future<void> _reloadAll() async {
    if (mounted) {
      setState(() {
        _isInitialLoading = true;
      });
    }

    await _refreshDetailsFromApi();
    if (!mounted) return;
    if (_isInitialLoading) {
      setState(() {
        _isInitialLoading = false;
      });
    }
  }

  List<_SeatStatusCardData> _buildCardsFromDetailsMap(
    Map<int, SeatStatusDetailsResponse> detailsMap,
  ) {
    final cards = <_SeatStatusCardData>[];
    for (final entry in detailsMap.entries) {
      cards.add(
        _buildCardFromDetails(sectionId: entry.key, details: entry.value),
      );
    }
    _sortCardsByCourseAndSection(cards);
    return cards;
  }

  Future<void> _applyDetailsUpdate(
    Map<int, SeatStatusDetailsResponse> detailsMap,
  ) async {
    if (!mounted || detailsMap.isEmpty) return;
    final updated = _buildCardsFromDetailsMap(detailsMap);
    if (_areCardListsDifferent(_cards, updated)) {
      _applyCardsSnapshot(updated, isInitialLoading: false);
    } else if (_isInitialLoading) {
      setState(() {
        _isInitialLoading = false;
      });
    }
  }

  Future<void> _openCourseCommunitySheet(_SeatStatusCardData item) async {
    final primarySchedule = item.classSchedule.isNotEmpty
        ? item.classSchedule.first
        : (item.labSchedule.isNotEmpty ? item.labSchedule.first : null);
    if (primarySchedule == null) {
      return;
    }
    final schedule = section.ClassSchedule(
      startTime: primarySchedule.startTime,
      endTime: primarySchedule.endTime,
      day: primarySchedule.day,
    );
    final isRamadan = await RamadanTiming.isRamadan();
    if (!mounted) return;
    await showBracuBottomSheet<void>(
      context,
      title: item.courseCode,
      initialChildSize: 0.88,
      builder: (sheetContext, textPrimary, textSecondary) {
        return CourseCommunitySheet.forClass(
          courseCode: item.courseCode,
          sectionName: item.sectionName,
          semesterLabel: 'Current',
          roomNumber: item.room.isNotEmpty ? item.room : item.labRoom,
          faculties: item.facultyInitial,
          consumedSeat: item.consumed,
          courseType: item.courseType,
          classSchedule: schedule,
          isRamadan: isRamadan,
          showActions: false,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return _buildPageContent(context);
  }
}

class _SeatStatusCard extends StatelessWidget {
  const _SeatStatusCard({
    required this.item,
    this.onTap,
    this.onPinTap,
    this.pinned = false,
  });

  final _SeatStatusCardData item;
  final VoidCallback? onTap;
  final VoidCallback? onPinTap;
  final bool pinned;

  @override
  Widget build(BuildContext context) {
    final textPrimary = BracuPalette.textPrimary(context);
    final textSecondary = BracuPalette.textSecondary(context);
    final theoryLabel = _titleCaseText(item.courseType);

    final card = BracuCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_headerLine(item.courseCode, item.sectionName)
                        .isNotEmpty)
                      Text(
                        _headerLine(item.courseCode, item.sectionName),
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: textPrimary,
                        ),
                      ),
                    if (item.courseName.trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        item.courseName,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: textSecondary,
                        ),
                      ),
                    ],
                    if (item.facultyInitial.trim().isNotEmpty ||
                        item.credits > 0) ...[
                      const SizedBox(height: 4),
                      RichText(
                        text: TextSpan(
                          style: TextStyle(
                            fontSize: 13,
                            color: textSecondary,
                          ),
                          children: [
                            if (item.facultyInitial.trim().isNotEmpty)
                              TextSpan(
                                text: item.facultyInitial,
                                style: TextStyle(
                                  color: textPrimary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            if (item.facultyInitial.trim().isNotEmpty &&
                                item.credits > 0)
                              TextSpan(
                                text: ' • ',
                                style: TextStyle(
                                  color: textSecondary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            if (item.credits > 0)
                              TextSpan(
                                text: '${item.credits} credits',
                                style: TextStyle(
                                  color: textSecondary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (onPinTap != null)
                Padding(
                  padding: const EdgeInsets.only(left: 8, top: 2),
                  child: IconButton(
                    onPressed: onPinTap,
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints.tightFor(width: 32, height: 32),
                    visualDensity: VisualDensity.compact,
                    splashRadius: 18,
                    tooltip: pinned ? 'Unpin section' : 'Pin section',
                    icon: Icon(
                      pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                      size: 18,
                      color: pinned ? BracuPalette.primary : textSecondary,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          if (item.classSchedule.isNotEmpty) ...[
            _SeatScheduleBlock(
              title: 'Class',
              lines: _scheduleLines(item.classSchedule),
            ),
          ],
          if (item.labSchedule.isNotEmpty ||
              item.labRoom.isNotEmpty ||
              item.labFaculties.isNotEmpty ||
              item.labSectionId != null) ...[
            if (item.labSchedule.isNotEmpty) ...[
              _SeatScheduleBlock(
                title: 'Lab',
                lines: _scheduleLines(item.labSchedule),
              ),
            ],
            if (_shouldShowLabMeta(item.labFaculties))
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  [
                    if (item.labFaculties.trim().isNotEmpty)
                      'Lab: ${item.labFaculties}',
                    if (item.labSectionId != null) 'ID: ${item.labSectionId}',
                  ].join(' • '),
                  style: TextStyle(
                    color: textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
          ],
          if (item.room.isNotEmpty || item.labRoom.isNotEmpty) ...[
            const SizedBox(height: 10),
            _RoomBlock(
              theoryLabel: theoryLabel,
              theoryRoom: item.room,
              labRoom: item.labRoom,
            ),
            const SizedBox(height: 12),
          ],
          if (item.midExamDate != null ||
              item.midExamStartTime != null ||
              item.midExamEndTime != null ||
              item.finalExamDate != null ||
              item.finalExamStartTime != null ||
              item.finalExamEndTime != null)
            Row(
              children: [
                Expanded(
                  child: _ExamInfo(
                    label: 'Mid',
                    date: item.midExamDate,
                    start: item.midExamStartTime,
                    end: item.midExamEndTime,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _ExamInfo(
                    label: 'Final',
                    date: item.finalExamDate,
                    start: item.finalExamStartTime,
                    end: item.finalExamEndTime,
                  ),
                ),
              ],
            ),
          if (item.midExamDate != null ||
              item.midExamStartTime != null ||
              item.midExamEndTime != null ||
              item.finalExamDate != null ||
              item.finalExamStartTime != null ||
              item.finalExamEndTime != null) ...[
            const SizedBox(height: 12),
            Divider(color: textSecondary.withValues(alpha: 0.2), height: 1),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              Expanded(
                child: _SeatMetric(
                  value: item.remaining,
                  label: 'Remaining',
                  color: item.remaining <= 0
                      ? BracuPalette.danger
                      : textPrimary,
                ),
              ),
              Expanded(
                child: _SeatMetric(
                  value: item.consumed,
                  label: 'Booked',
                  color: textPrimary,
                ),
              ),
              Expanded(
                child: _SeatMetric(
                  value: item.total,
                  label: 'Total Seats',
                  color: textPrimary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: card,
      ),
    );
  }

  List<String> _scheduleLines(
    List<SeatStatusClassSchedule> schedules,
  ) {
    if (schedules.isEmpty) return const <String>[];
    final lines = schedules.map((entry) {
      final day = formatWeekdayTitle(entry.day);
      final time = formatTimeRange(entry.startTime, entry.endTime);
      return '$day $time'.trim();
    }).toList();
    return lines.where((line) => line.trim().isNotEmpty).toList();
  }

  String _headerLine(String courseCode, String sectionName) {
    final code = courseCode.trim();
    final section = sectionName.trim();
    if (code.isEmpty && section.isEmpty) return '';
    if (code.isEmpty) return section;
    if (section.isEmpty) return code;
    return '$code - $section';
  }

  bool _shouldShowLabMeta(String labFaculties) {
    final cleaned = labFaculties.trim();
    if (cleaned.isEmpty) return false;
    return cleaned.toLowerCase() != 'tba';
  }
}

class _RoomBlock extends StatelessWidget {
  const _RoomBlock({
    required this.theoryLabel,
    required this.theoryRoom,
    required this.labRoom,
  });

  final String theoryLabel;
  final String theoryRoom;
  final String labRoom;

  @override
  Widget build(BuildContext context) {
    final lines = <InlineSpan>[];
    if (theoryRoom.trim().isNotEmpty) {
      lines.add(
        TextSpan(
          text: '$theoryLabel: ',
          style: TextStyle(
            color: BracuPalette.textSecondary(context),
            fontWeight: FontWeight.w500,
          ),
        ),
      );
      lines.add(
        TextSpan(
          text: theoryRoom.trim(),
          style: TextStyle(
            color: BracuPalette.textPrimary(context),
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }
    if (theoryRoom.trim().isNotEmpty && labRoom.trim().isNotEmpty) {
      lines.add(
        const TextSpan(
          text: '\n',
        ),
      );
    }
    if (labRoom.trim().isNotEmpty) {
      lines.add(
        TextSpan(
          text: 'Lab: ',
          style: TextStyle(
            color: BracuPalette.textSecondary(context),
            fontWeight: FontWeight.w500,
          ),
        ),
      );
      lines.add(
        TextSpan(
          text: labRoom.trim(),
          style: TextStyle(
            color: BracuPalette.textPrimary(context),
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }
    if (lines.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Room:',
          style: TextStyle(
            color: BracuPalette.textSecondary(context),
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 3),
        RichText(
          text: TextSpan(
            style: TextStyle(
              fontSize: 14,
              height: 1.25,
              color: BracuPalette.textPrimary(context),
              fontWeight: FontWeight.w700,
            ),
            children: lines,
          ),
        ),
      ],
    );
  }
}

String _titleCaseText(String value) {
  final cleaned = value
      .replaceAll(RegExp(r'[^a-z0-9]+', caseSensitive: false), ' ')
      .trim();
  if (cleaned.isEmpty) return '';
  return cleaned
      .split(RegExp(r'\s+'))
      .map((part) {
        if (part.isEmpty) return part;
        return part[0].toUpperCase() + part.substring(1).toLowerCase();
      })
      .join(' ');
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.icon,
    required this.label,
    this.selected = false,
    this.onTap,
    this.showArrow = true,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final bool showArrow;

  @override
  Widget build(BuildContext context) {
    return BracuSelectChip(
      icon: icon,
      label: label,
      selected: selected,
      onTap: onTap,
      showArrow: showArrow,
      compact: true,
      borderRadius: 16,
    );
  }
}

class _SeatScheduleBlock extends StatelessWidget {
  const _SeatScheduleBlock({required this.title, required this.lines});

  final String title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$title:',
          style: TextStyle(
            color: BracuPalette.textSecondary(context),
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 3),
        for (final line in lines)
          Text(
            line,
            style: TextStyle(
              color: BracuPalette.textPrimary(context),
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
      ],
    );
  }
}

class _ExamInfo extends StatelessWidget {
  const _ExamInfo({
    required this.label,
    required this.date,
    required this.start,
    required this.end,
  });

  final String label;
  final String? date;
  final String? start;
  final String? end;

  @override
  Widget build(BuildContext context) {
    final dateValue = _formatExamDate(date);
    final timeValue = _formatExamTime(start, end);
    final hasDate = dateValue.isNotEmpty;
    final hasTime = timeValue.isNotEmpty;
    if (!hasDate && !hasTime) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label:',
          style: TextStyle(
            color: BracuPalette.textSecondary(context),
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 3),
        if (hasDate)
          Text(
            dateValue,
            style: TextStyle(
              color: BracuPalette.textPrimary(context),
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        if (hasDate && hasTime) const SizedBox(height: 1),
        if (hasTime)
          Text(
            timeValue,
            style: TextStyle(
              color: BracuPalette.textSecondary(context),
              fontSize: 11.5,
            ),
          ),
      ],
    );
  }

  String _formatExamDate(String? raw) {
    if (raw == null || raw.trim().isEmpty) return '';
    final parsed = BracuTime.parseDate(raw);
    if (parsed == null) return raw.trim();
    return DateFormat('MMM d, y').format(parsed);
  }

  String _formatExamTime(String? start, String? end) {
    final range = formatTimeRange(start, end);
    if (range.isEmpty) return '';
    return range;
  }
}

class _SeatMetric extends StatelessWidget {
  const _SeatMetric({
    required this.value,
    required this.label,
    required this.color,
  });

  final int value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          '$value',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: BracuPalette.textSecondary(context),
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _SeatStatusCardData {
  const _SeatStatusCardData({
    required this.sectionId,
    required this.courseCode,
    required this.sectionName,
    required this.courseName,
    required this.facultyInitial,
    required this.facultyMeta,
    required this.credits,
    required this.room,
    required this.courseType,
    required this.classSchedule,
    required this.labSchedule,
    required this.labRoom,
    required this.labCourseCode,
    required this.labName,
    required this.labFaculties,
    required this.labSectionId,
    required this.midExamDate,
    required this.midExamStartTime,
    required this.midExamEndTime,
    required this.finalExamDate,
    required this.finalExamStartTime,
    required this.finalExamEndTime,
    required this.remaining,
    required this.consumed,
    required this.total,
    required this.searchToken,
  });

  final int sectionId;
  final String courseCode;
  final String sectionName;
  final String courseName;
  final String facultyInitial;
  final String facultyMeta;
  final int credits;
  final String room;
  final String courseType;
  final List<SeatStatusClassSchedule> classSchedule;
  final List<SeatStatusClassSchedule> labSchedule;
  final String labRoom;
  final String labCourseCode;
  final String labName;
  final String labFaculties;
  final int? labSectionId;
  final String? midExamDate;
  final String? midExamStartTime;
  final String? midExamEndTime;
  final String? finalExamDate;
  final String? finalExamStartTime;
  final String? finalExamEndTime;
  final int remaining;
  final int consumed;
  final int total;
  final String searchToken;

  _SeatStatusCardData copyWith({int? remaining, int? consumed, int? total}) {
    return _SeatStatusCardData(
      sectionId: sectionId,
      courseCode: courseCode,
      sectionName: sectionName,
      courseName: courseName,
      facultyInitial: facultyInitial,
      facultyMeta: facultyMeta,
      credits: credits,
      room: room,
      courseType: courseType,
      classSchedule: classSchedule,
      labSchedule: labSchedule,
      labRoom: labRoom,
      labCourseCode: labCourseCode,
      labName: labName,
      labFaculties: labFaculties,
      labSectionId: labSectionId,
      midExamDate: midExamDate,
      midExamStartTime: midExamStartTime,
      midExamEndTime: midExamEndTime,
      finalExamDate: finalExamDate,
      finalExamStartTime: finalExamStartTime,
      finalExamEndTime: finalExamEndTime,
      remaining: remaining ?? this.remaining,
      consumed: consumed ?? this.consumed,
      total: total ?? this.total,
      searchToken: searchToken,
    );
  }
}
