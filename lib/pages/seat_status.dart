import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:preconnect/api/api_client.dart';
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/api/seat_status.dart';
import 'package:preconnect/pages/home_tab.dart';
import 'package:preconnect/model/section_info.dart' as section;
import 'package:preconnect/pages/notifications.dart';
import 'package:preconnect/pages/friend_schedule_sections/friend_header.dart';
import 'package:preconnect/pages/shared_widgets/course_community_sheet.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/ramadan.dart';
import 'package:preconnect/tools/preconnect_constants.dart';
import 'package:preconnect/tools/token_storage.dart';
import 'package:preconnect/tools/time_utils.dart';
import 'package:preconnect/api/fcm.dart';
part 'shared_widgets/seat_status_methods.dart';

String seatStatusFacultySummaryLabel(section.SectionFaculty? faculty) {
  final staffName = faculty?.staffName.trim() ?? '';
  if (staffName.isEmpty || staffName.toUpperCase() == 'TBA') {
    return 'TBA';
  }
  final shortName = faculty?.shortName.trim() ?? '';
  if (shortName.isNotEmpty) return shortName;
  return '';
}

String seatStatusFacultyDetailLabel(section.SectionFaculty? faculty) {
  final staffName = faculty?.staffName.trim() ?? '';
  if (staffName.isEmpty || staffName.toUpperCase() == 'TBA') return '';
  final pieces = <String>[
    faculty?.staffName.trim() ?? '',
    faculty?.email.trim() ?? '',
  ];
  return pieces.where((value) => value.trim().isNotEmpty).join(' ').trim();
}

String seatStatusFacultySearchText(section.SectionFaculty? faculty) {
  final pieces = <String>[
    seatStatusFacultySummaryLabel(faculty),
    seatStatusFacultyDetailLabel(faculty),
  ];
  return pieces.where((value) => value.trim().isNotEmpty).join(' ').trim();
}

bool seatStatusFacultyHasVisuals(section.SectionFaculty? faculty) {
  final staffName = faculty?.staffName.trim() ?? '';
  if (staffName.isEmpty || staffName.toUpperCase() == 'TBA') return false;
  return staffName.isNotEmpty ||
      (faculty?.email.trim().isNotEmpty == true) ||
      (faculty?.imgUrl?.trim().isNotEmpty == true);
}

class SeatStatusPage extends StatefulWidget {
  const SeatStatusPage({super.key});

  static Future<void> preload() async {
    await SeatStatusService.preload();
  }

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
  String _selectedTimeFilter = '';
  @override
  void initState() {
    super.initState();
    _seedCachedCards();
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

  void _seedCachedCards() {
    final cachedDetails = _service.cachedDetails;
    if (cachedDetails == null) return;
    final cards = _buildCardsFromDetailsMap(cachedDetails);
    _cards
      ..clear()
      ..addAll(cards);
    _visibleCards
      ..clear()
      ..addAll(
        _filterCards(
          cards,
          _searchQuery,
          availableOnly: _availableOnly,
          dayFilter: _selectedDayFilter,
          timeFilter: _selectedTimeFilter,
        ),
      );
    _isInitialLoading = false;
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

  void _updateSeatStatusState(VoidCallback update) {
    if (!mounted) return;
    setState(update);
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
    _SeatStatusCardData? card;
    for (final c in _cards) {
      if (c.sectionId == sectionId) {
        card = c;
        break;
      }
    }

    setState(() {
      if (willPin) {
        _pinnedSections.add(key);
      } else {
        _pinnedSections.remove(key);
      }
    });

    await CoursePinStore.save(_pinScope, _pinnedSections);

    final initialRefreshed = List<_SeatStatusCardData>.from(_cards);
    _sortCardsByCourseAndSection(initialRefreshed);
    _applyCardsSnapshot(initialRefreshed, isInitialLoading: false);

    final fcmSupported = FCMService.instance.isSupported;

    if (willPin && fcmSupported) {
      try {
        final hasPerm = await FCMService.instance.isNotificationPermissionGranted();
        if (!hasPerm) {
          final granted = await FCMService.instance.requestNotificationPermission();
          if (!granted && mounted) {
            showAppSnackBar(
              context,
              'Notification permission is disabled. Enable it in Settings to receive push alerts.',
            );
          }
        }
      } catch (e) {
        debugPrint("Error handling permission request during pin: $e");
      }
    }

    final topic = PreconnectPushConfig.seatTopic(key);
    bool syncOk = false;
    try {
      if (!fcmSupported) {
        syncOk = true;
      } else {
        if (willPin) {
          syncOk = await FCMService.instance.subscribeToTopic(topic);
        } else {
          syncOk = await FCMService.instance.unsubscribeFromTopic(topic);
        }
      }
    } catch (_) {
      syncOk = false;
    }

    if (!syncOk && willPin) {
      setState(() {
        _pinnedSections.remove(key);
      });
      await CoursePinStore.save(_pinScope, _pinnedSections);

      if (!mounted) return;
      final revertRefreshed = List<_SeatStatusCardData>.from(_cards);
      _sortCardsByCourseAndSection(revertRefreshed);
      _applyCardsSnapshot(revertRefreshed, isInitialLoading: false);

      showAppSnackBar(
        context,
        'Failed to sync seat alert. Please check your internet connection.',
      );
      return;
    }

    if (willPin && fcmSupported && card != null) {
      unawaited(
        FCMService.instance.sendConfirmationNotification(
          card.courseCode,
          card.sectionName,
        ),
      );
    }

    if (!mounted) return;
    final String message;
    if (card != null) {
      if (!fcmSupported) {
        message = willPin
            ? '${card.courseCode} Section ${card.sectionName} pinned locally'
            : '${card.courseCode} Section ${card.sectionName} unpinned';
      } else {
        final status = willPin ? 'alerts enabled' : 'alerts disabled';
        message = '${card.courseCode} Section ${card.sectionName} $status';
      }
    } else {
      if (!fcmSupported) {
        message = willPin ? 'Pinned locally' : 'Unpinned';
      } else {
        message = 'Seat alerts ${willPin ? 'enabled' : 'disabled'}';
      }
    }
    showAppSnackBar(context, message);
  }

  Future<void> _reloadAll() async {
    final hasCachedCards = _cards.isNotEmpty;
    final hasCachedDetails = _service.cachedDetails != null;
    if (mounted && !hasCachedCards && !hasCachedDetails) {
      setState(() {
        _isInitialLoading = true;
      });
    }

    await _refreshDetailsFromApi(forceRefresh: true);
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
    final courseHeader = _headerLine(item.courseCode, item.sectionName);
    final faculty = item.faculty;
    final facultyName = faculty?.staffName.trim() ?? '';
    final facultyEmail = faculty?.email.trim() ?? '';
    final classLines = _scheduleLines(item.classSchedule);
    final labLines = _scheduleLines(item.labSchedule);
    final hasMidExam = _hasExam(
      item.midExamDate,
      item.midExamStartTime,
      item.midExamEndTime,
    );
    final hasFinalExam = _hasExam(
      item.finalExamDate,
      item.finalExamStartTime,
      item.finalExamEndTime,
    );

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
                    if (courseHeader.isNotEmpty)
                      Text(
                        courseHeader,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: textPrimary,
                        ),
                      ),
                    if (item.courseName.trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        item.courseName.trim(),
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
                          style: TextStyle(fontSize: 13, color: textSecondary),
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
                    if (seatStatusFacultyHasVisuals(faculty)) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          if (faculty?.imgUrl?.trim().isNotEmpty == true) ...[
                            FriendAvatar(
                              name: facultyName.isNotEmpty
                                  ? facultyName
                                  : courseHeader,
                              photoUrl: faculty!.imgUrl,
                              size: 40,
                              radius: 20,
                            ),
                            const SizedBox(width: 10),
                          ],
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (facultyName.isNotEmpty)
                                  Text(
                                    facultyName,
                                    style: TextStyle(
                                      color: textPrimary,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                if (facultyEmail.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  InkWell(
                                    borderRadius: BorderRadius.circular(6),
                                    onTap: () =>
                                        openMailComposer(context, facultyEmail),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 2,
                                      ),
                                      child: Text(
                                        facultyEmail,
                                        style: TextStyle(
                                          color: textSecondary,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              if (onPinTap != null)
                Padding(
                  padding: const EdgeInsets.only(left: 8, top: 2),
                  child: _PinIconButton(pinned: pinned, onTap: onPinTap!),
                ),
            ],
          ),
          if (classLines.isNotEmpty) ...[
            const SizedBox(height: 14),
            _SeatScheduleBlock(title: 'Class', lines: classLines),
          ],
          if (labLines.isNotEmpty) ...[
            const SizedBox(height: 12),
            _SeatScheduleBlock(title: 'Lab', lines: labLines),
          ],
          if (item.room.isNotEmpty || item.labRoom.isNotEmpty) ...[
            const SizedBox(height: 12),
            _RoomBlock(
              theoryLabel: theoryLabel,
              theoryRoom: item.room,
              labRoom: item.labRoom,
            ),
            const SizedBox(height: 12),
          ],
          if (hasMidExam || hasFinalExam) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _ExamBlock(
                    label: 'Mid',
                    date: item.midExamDate,
                    start: item.midExamStartTime,
                    end: item.midExamEndTime,
                    textPrimary: textPrimary,
                    textSecondary: textSecondary,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _ExamBlock(
                    label: 'Final',
                    date: item.finalExamDate,
                    start: item.finalExamStartTime,
                    end: item.finalExamEndTime,
                    textPrimary: textPrimary,
                    textSecondary: textSecondary,
                  ),
                ),
              ],
            ),
          ],
          if (item.remaining >= 0 || item.consumed >= 0 || item.total >= 0) ...[
            const SizedBox(height: 12),
            Divider(color: textSecondary.withValues(alpha: 0.2), height: 1),
            const SizedBox(height: 12),
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
                    label: 'Total',
                    color: textPrimary,
                  ),
                ),
              ],
            ),
          ],
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

  bool _hasExam(String? date, String? start, String? end) {
    return (date ?? '').trim().isNotEmpty ||
        (start ?? '').trim().isNotEmpty ||
        (end ?? '').trim().isNotEmpty;
  }

  List<String> _scheduleLines(List<SeatStatusClassSchedule> schedules) {
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
      lines.add(const TextSpan(text: '\n'));
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

class _PinIconButton extends StatelessWidget {
  const _PinIconButton({required this.pinned, required this.onTap});

  final bool pinned;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 44, height: 44),
      visualDensity: VisualDensity.compact,
      splashRadius: 22,
      icon: Icon(
        pinned ? Icons.notifications_rounded : Icons.notifications_none_rounded,
        size: 28,
        color: pinned
            ? BracuPalette.primary
            : BracuPalette.textSecondary(context),
      ),
    );
  }
}

class _SeatStatusCardData {
  const _SeatStatusCardData({
    required this.sectionId,
    required this.courseCode,
    required this.sectionName,
    required this.courseName,
    required this.faculty,
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
    required this.timetables,
    required this.searchToken,
  });

  final int sectionId;
  final String courseCode;
  final String sectionName;
  final String courseName;
  final section.SectionFaculty? faculty;
  final String facultyInitial;
  final String facultyMeta;
  final int credits;
  final String room;
  final String courseType;
  final List<SeatStatusClassSchedule> classSchedule;
  final List<SeatStatusClassSchedule> labSchedule;
  final List<SeatTimetable> timetables;
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
      faculty: faculty,
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
      timetables: timetables,
    );
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

class _ExamBlock extends StatelessWidget {
  const _ExamBlock({
    required this.label,
    required this.date,
    required this.start,
    required this.end,
    required this.textPrimary,
    required this.textSecondary,
  });

  final String label;
  final String? date;
  final String? start;
  final String? end;
  final Color textPrimary;
  final Color textSecondary;

  @override
  Widget build(BuildContext context) {
    final dateLabel = formatDate(date);
    final timeLabel = formatTimeRange(start, end);
    final hasDate = dateLabel.isNotEmpty;
    final hasTime = timeLabel.isNotEmpty;
    if (!hasDate && !hasTime) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label:',
          style: TextStyle(
            color: textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 3),
        if (hasDate)
          Text(
            dateLabel,
            style: TextStyle(
              color: textPrimary,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        if (hasDate && hasTime) const SizedBox(height: 1),
        if (hasTime)
          Text(
            timeLabel,
            style: TextStyle(color: textSecondary, fontSize: 11.5),
          ),
      ],
    );
  }
}
