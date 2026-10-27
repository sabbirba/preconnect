import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:preconnect/api/api_client.dart';
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/api/seat_status.dart';
import 'package:preconnect/pages/home_tab.dart';
import 'package:preconnect/model/section_info.dart' as section;
import 'package:preconnect/model/seat_timetable.dart';
import 'package:preconnect/pages/notifications.dart';
import 'package:preconnect/pages/friend_sections/friend_header.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/preconnect_constants.dart';
import 'package:preconnect/tools/token_storage.dart';
import 'package:preconnect/api/fcm.dart';
import 'package:preconnect/tools/ramadan.dart';
import 'package:preconnect/tools/refresh_bus.dart';
import 'package:preconnect/pages/shared_widgets/faculty_sheet.dart';
import 'package:preconnect/pages/shared_widgets/seat_filters.dart';
import 'package:preconnect/tools/string_utils.dart';
import 'package:preconnect/pages/shared_widgets/seat_blocks.dart';
import 'package:preconnect/tools/app_log.dart';
part 'shared_widgets/seat_status.dart';

String seatStatusFacultySummaryLabel(section.SectionFaculty? faculty) {
  if (faculty == null) return 'TBA';
  final shortName = faculty.shortName.trim();
  if (shortName.isNotEmpty && shortName.toUpperCase() != 'TBA') {
    return shortName;
  }
  final staffName = faculty.staffName.trim();
  if (staffName.isNotEmpty && staffName.toUpperCase() != 'TBA') {
    return staffName;
  }
  return 'TBA';
}

String seatStatusFacultyDetailLabel(section.SectionFaculty? faculty) {
  if (faculty == null) return '';
  final name = faculty.staffName.trim();
  final email = faculty.email.trim();
  if (name.isEmpty) return email;
  if (email.isEmpty) return name;
  return '$name $email';
}

String seatStatusFacultySearchText(section.SectionFaculty? faculty) {
  final pieces = <String>[
    seatStatusFacultySummaryLabel(faculty),
    seatStatusFacultyDetailLabel(faculty),
  ];
  return pieces.where((value) => value.trim().isNotEmpty).join(' ').trim();
}

bool seatStatusFacultyHasVisuals(section.SectionFaculty? faculty) {
  if (faculty == null) return false;
  return faculty.shortName.trim().isNotEmpty ||
      faculty.staffName.trim().isNotEmpty ||
      faculty.email.trim().isNotEmpty ||
      faculty.imgUrl?.trim().isNotEmpty == true;
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
    with WidgetsBindingObserver, RefreshBusState {
  static const String _pinScope = 'seat_status';
  final SeatStatusService _service = SeatStatusService();
  final List<_SeatStatusCardData> _cards = <_SeatStatusCardData>[];
  final List<_SeatStatusCardData> _visibleCards = <_SeatStatusCardData>[];
  final Set<String> _pinnedSections = <String>{};
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;

  List<String> _archiveSemesters = [];
  String _selectedArchive = '';
  int _requestGeneration = 0;
  bool _isInitialLoading = true;
  String _searchQuery = '';
  bool _isDetailsRefreshing = false;
  bool _availableOnly = false;
  bool _labOnly = false;
  String _selectedDayFilter = '';
  String _selectedModeFilter = '';
  SeatTimetable _selectedTimeFilter = SeatTimetable(startTime: '', endTime: '');
  bool _isRamadan = false;

  @override
  void initState() {
    super.initState();
    RamadanTiming.isRamadan().then((value) {
      if (!mounted) return;
      setState(() {
        _isRamadan = value;
      });
    });
    _seedCachedCards();
    _searchController.addListener(() {
      _searchDebounce?.cancel();
      _searchDebounce = Timer(const Duration(milliseconds: 150), () {
        if (!mounted) return;
        final next = _searchController.text.trim().toLowerCase();
        _updateSearchQuery(next);
      });
    });
    unawaited(_loadArchiveSemesters());
    unawaited(_loadPins());
    unawaited(_refreshDetailsFromApi());
    WidgetsBinding.instance.addObserver(this);
    HomeTabRegistry.activeTab.addListener(_onActiveTabChanged);
    bindRefreshBus(_onRefreshSignal);
  }

  Future<void> _loadArchiveSemesters() async {
    try {
      final semesters = await _service.fetchArchiveSemesters();
      if (!mounted) return;
      setState(() => _archiveSemesters = semesters);
    } catch (_) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        'Could not load archived semesters. Pull to refresh to retry.',
      );
    }
  }

  void _selectArchive(String semester) {
    if (_selectedArchive == semester) return;
    setState(() {
      _selectedArchive = semester;
      _requestGeneration++;
      _isDetailsRefreshing = false;
      _isInitialLoading = true;
      _cards.clear();
      _visibleCards.clear();
    });
    unawaited(_refreshDetailsFromApi());
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
          modeFilter: _selectedModeFilter,
          timeFilter: _selectedTimeFilter,
        ),
      );
    _isInitialLoading = false;
  }

  @override
  void dispose() {
    unbindRefreshBus(_onRefreshSignal);
    WidgetsBinding.instance.removeObserver(this);
    HomeTabRegistry.activeTab.removeListener(_onActiveTabChanged);
    _searchDebounce?.cancel();

    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _refreshIfActive();
  }

  void _onActiveTabChanged() {
    if (!mounted) return;
    _refreshIfActive();
  }

  void _onRefreshSignal() {
    if (!mounted) return;
    if (_selectedArchive.isNotEmpty) return;
    final reason = refreshBusReason;
    if (reason == 'seat_status' ||
        reason == 'mercure_event' ||
        reason == 'cache_cleared' ||
        reason == 'home_dashboard') {
      unawaited(_refreshDetailsFromApi());
    }
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

  void _togglePin(int sectionId) {
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

    final initialRefreshed = List<_SeatStatusCardData>.from(_cards);
    _sortCardsByCourseAndSection(initialRefreshed);
    _applyCardsSnapshot(initialRefreshed, isInitialLoading: false);

    final fcmSupported = FCMService.instance.isSupported;
    if (mounted) {
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

    unawaited(() async {
      try {
        await CoursePinStore.save(_pinScope, _pinnedSections);

        if (willPin && fcmSupported) {
          try {
            final hasPerm = await FCMService.instance
                .isNotificationPermissionGranted();
            if (!hasPerm) {
              final granted = await FCMService.instance
                  .requestNotificationPermission();
              if (!granted && mounted) {
                showAppSnackBar(
                  context,
                  'Notification permission is disabled. Enable it in Settings to receive push alerts.',
                );
              }
            }
          } catch (_) {}
        }

        final topic = PreConnectPushConfig.seatTopic(key);
        bool syncOk = false;
        try {
          if (!fcmSupported) {
            syncOk = true;
          } else if (willPin) {
            syncOk = await FCMService.instance.subscribeToTopic(topic);
          } else {
            unawaited(FCMService.instance.unsubscribeFromTopic(topic));
            syncOk = true;
          }
        } catch (_) {
          syncOk = false;
        }

        if (!syncOk && willPin) {
          if (mounted) {
            setState(() {
              _pinnedSections.remove(key);
            });
          } else {
            _pinnedSections.remove(key);
          }
          await CoursePinStore.save(_pinScope, _pinnedSections);

          if (mounted) {
            final revertRefreshed = List<_SeatStatusCardData>.from(_cards);
            _sortCardsByCourseAndSection(revertRefreshed);
            _applyCardsSnapshot(revertRefreshed, isInitialLoading: false);

            showAppSnackBar(
              context,
              'Failed to sync seat alert. Please check your internet connection.',
            );
          }
          return;
        }

        if (card != null) {
          unawaited(
            FCMService.instance.syncSeatEmailAlert(
              card.courseCode,
              card.sectionName,
              subscribe: willPin,
            ),
          );
          unawaited(
            FCMService.instance.syncWatchlistSnapshot(
              card.courseCode,
              card.sectionName,
              subscribe: willPin,
            ),
          );
        }

        if (willPin && fcmSupported && card != null) {
          unawaited(
            FCMService.instance.sendConfirmationNotification(
              card.courseCode,
              card.sectionName,
            ),
          );
        }
      } catch (_) {}
    }());
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

  void _applyDetailsUpdate(Map<int, SeatStatusDetailsResponse> detailsMap) {
    if (!mounted) return;
    final updated = _buildCardsFromDetailsMap(detailsMap);
    if (_areCardListsDifferent(_cards, updated)) {
      _applyCardsSnapshot(updated, isInitialLoading: false);
    } else if (_isInitialLoading) {
      setState(() {
        _isInitialLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return _buildPageContent(context);
  }
}

class _SeatStatusCard extends StatelessWidget {
  const _SeatStatusCard({
    required this.item,
    this.onPinTap,
    this.pinned = false,
    this.onTap,
  });

  final _SeatStatusCardData item;
  final VoidCallback? onPinTap;
  final bool pinned;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final textPrimary = AppPalette.textPrimary(context);
    final textSecondary = AppPalette.textSecondary(context);
    final theoryLabel = seatTitleCase(item.courseType);
    final courseHeader = _headerLine(item.courseCode, item.sectionName);
    final faculty = item.faculty;
    final facultyName = faculty?.staffName.trim() ?? '';
    final facultyEmail = faculty?.email.trim() ?? '';
    final classLines = seatScheduleLines(item.classSchedule);
    final labLines = seatScheduleLines(item.labSchedule);
    final hasMidExam = hasExamSchedule(
      item.midExamDate,
      item.midExamStartTime,
      item.midExamEndTime,
    );
    final hasFinalExam = hasExamSchedule(
      item.finalExamDate,
      item.finalExamStartTime,
      item.finalExamEndTime,
    );

    final card = AppCard(
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
                      const Gap(2),
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
                      const Gap(4),
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
                      const Gap(8),
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
                            const Gap(12),
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
                                  const Gap(2),
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
            const Gap(12),
            SeatScheduleBlock(title: 'Class', lines: classLines),
          ],
          if (labLines.isNotEmpty) ...[
            const Gap(12),
            SeatScheduleBlock(title: 'Lab', lines: labLines),
          ],
          if (item.room.isNotEmpty || item.labRoom.isNotEmpty) ...[
            const Gap(12),
            SeatRoomBlock(
              theoryLabel: theoryLabel,
              theoryRoom: item.room,
              labRoom: item.labRoom,
            ),
            const Gap(12),
          ],
          if (hasMidExam || hasFinalExam) ...[
            const Gap(12),
            Row(
              children: [
                Expanded(
                  child: SeatExamBlock(
                    label: 'Mid',
                    date: item.midExamDate,
                    start: item.midExamStartTime,
                    end: item.midExamEndTime,
                    textPrimary: textPrimary,
                    textSecondary: textSecondary,
                  ),
                ),
                const Gap(16),
                Expanded(
                  child: SeatExamBlock(
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
          if (item.total >= 0 ||
              item.consumed >= 0 ||
              item.remaining != -1) ...[
            const Gap(12),
            Divider(color: textSecondary.withValues(alpha: 0.2), height: 1),
            const Gap(12),
            Row(
              children: [
                Expanded(
                  child: SeatMetric(
                    value: item.remaining,
                    label: 'Remaining',
                    color: item.remaining <= 0
                        ? AppPalette.danger
                        : textPrimary,
                  ),
                ),
                Expanded(
                  child: SeatMetric(
                    value: item.consumed,
                    label: 'Booked',
                    color: textPrimary,
                  ),
                ),
                Expanded(
                  child: SeatMetric(
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
    if (onTap == null) {
      return card;
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: card,
      ),
    );
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
        color: pinned ? AppPalette.primary : AppPalette.textSecondary(context),
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
