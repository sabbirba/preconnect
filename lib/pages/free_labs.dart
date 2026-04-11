import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:preconnect/api/seat_status_service.dart';
import 'package:preconnect/model/seat_status_info.dart';
import 'package:preconnect/pages/home_tab.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/time_utils.dart';

class FreeLabsPage extends StatefulWidget {
  const FreeLabsPage({super.key});

  @override
  State<FreeLabsPage> createState() => _FreeLabsPageState();
}

class _FreeLabsPageState extends State<FreeLabsPage> {
  late Future<List<_FreeRoomSlot>> _future;
  List<_FreeRoomSlot> _lastSlots = const <_FreeRoomSlot>[];
  List<_FreeRoomSlot> _lastAllSlots = const <_FreeRoomSlot>[];
  final ScrollController _scrollController = ScrollController();
  GlobalKey? _highlightKey;
  String? _lastHighlightToken;
  bool _didScroll = false;
  bool _scrollRetry = false;
  _RoomFilter _selectedFilter = _RoomFilter.labs;
  bool _showNextDayAfterHours = false;

  @override
  void initState() {
    super.initState();
    _future = _loadSlots();
    HomeTabRegistry.activeTab.addListener(_onActiveTabChanged);
  }

  @override
  void dispose() {
    HomeTabRegistry.activeTab.removeListener(_onActiveTabChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _onActiveTabChanged() {
    if (!mounted) return;
    if (HomeTabRegistry.activeTab.value != HomeTab.freeLabs) return;
    if (!_showNextDayAfterHours) return;
    final next = _loadSlots();
    setState(() {
      _showNextDayAfterHours = false;
      _future = next;
      _didScroll = false;
      _scrollRetry = false;
    });
    next.then((slots) {
      if (!mounted) return;
      setState(() {
        _lastSlots = slots;
      });
    });
  }

  DateTime _nextSupportedDate(DateTime source) {
    var target = source;
    while (target.weekday == DateTime.friday) {
      target = target.add(const Duration(days: 1));
    }
    return target;
  }

  DateTime _displayDate({DateTime? now}) {
    final current = now ?? DateTime.now();
    var target = _nextSupportedDate(
      DateTime(current.year, current.month, current.day),
    );
    if (_showNextDayAfterHours && _isAfterHours(now: current)) {
      target = _nextSupportedDate(target.add(const Duration(days: 1)));
    }
    return target;
  }

  bool _isAfterHours({DateTime? now}) {
    final current = now ?? DateTime.now();
    return current.hour * 60 + current.minute >= 20 * 60;
  }

  DateTime get _activeDate => _displayDate();

  String get _activeDayName => DateFormat('EEEE').format(_activeDate);

  bool _isViewingFutureDate() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final display = _displayDate(now: now);
    return display.isAfter(today);
  }

  bool _shouldOfferNextDayLabs() {
    return !_showNextDayAfterHours && _isAfterHours();
  }

  DateTime _nextLabsDate() {
    final now = DateTime.now();
    final tomorrow = DateTime(
      now.year,
      now.month,
      now.day,
    ).add(const Duration(days: 1));
    return _nextSupportedDate(tomorrow);
  }

  Future<List<_FreeRoomSlot>> _loadSlots({bool forceRefresh = false}) async {
    final allSlots = await _loadAllSlots(forceRefresh: forceRefresh);
    _lastAllSlots = allSlots;
    return _applySelectedFilter(allSlots);
  }

  Future<List<_FreeRoomSlot>> _loadAllSlots({bool forceRefresh = false}) async {
    if (!forceRefresh) {
      final cachedSlots = await _readCachedSlots();
      if (cachedSlots.isNotEmpty) return cachedSlots;
    }

    final service = SeatStatusService();
    final details = forceRefresh
        ? await service.fetchAllSectionsDetailsFromApi()
        : await service
              .loadCachedDetails(maxAge: const Duration(days: 30))
              .then((cached) async {
                if (cached.isNotEmpty) return cached;
                return service.fetchAllSectionsDetailsFromApi();
              });
    final allSlots = _buildFreeRoomSlots(
      details.values.toList(),
      _activeDayName,
    );
    await _writeCachedSlots(allSlots);
    return allSlots;
  }

  Future<void> _refresh() async {
    final next = _loadSlots(forceRefresh: true);
    setState(() {
      _future = next;
      _didScroll = false;
      _scrollRetry = false;
    });
    final slots = await next;
    if (!mounted) return;
    setState(() {
      _lastSlots = slots;
    });
  }

  void _attemptScrollToHighlight() {
    attemptScrollToHighlightedKey(
      highlightKey: _highlightKey,
      hasRetried: _scrollRetry,
      alignment: 0.18,
      retry: () {
        _scrollRetry = true;
        if (mounted) {
          setState(() {});
        }
      },
      onScrolled: () {
        _didScroll = true;
      },
    );
  }

  Future<void> _changeFilter(_RoomFilter selected) async {
    if (selected == _selectedFilter) return;
    final next = _lastAllSlots.isNotEmpty
        ? Future<List<_FreeRoomSlot>>.value(
            _applyFilter(_lastAllSlots, selected),
          )
        : _loadSlots();
    setState(() {
      _selectedFilter = selected;
      _future = next;
      _didScroll = false;
      _scrollRetry = false;
    });
    final slots = await next;
    if (!mounted) return;
    setState(() {
      _lastSlots = slots;
    });
  }

  String _dynamicHeaderTitle() {
    return switch (_selectedFilter) {
      _RoomFilter.labs => 'Free Labs',
      _RoomFilter.classes => 'Free Classes',
      _RoomFilter.theater => 'Free Theaters',
    };
  }

  String _dynamicEmptyMessage() {
    final weekday = formatWeekdayTitle(_activeDayName);
    return switch (_selectedFilter) {
      _RoomFilter.labs => 'No free labs found for $weekday.',
      _RoomFilter.classes => 'No free classes found for $weekday.',
      _RoomFilter.theater => 'No free theaters found for $weekday.',
    };
  }

  @override
  Widget build(BuildContext context) {
    return BracuPageScaffold(
      title: _dynamicHeaderTitle(),
      subtitle: _headerDayLabel(),
      icon: Icons.computer_outlined,
      actions: [
        BracuSelectDropdownChip<_RoomFilter>(
          label: _selectedFilter.label,
          title: 'Choose Filter',
          subtitle: 'Filter free labs by room type',
          selectedValue: _selectedFilter,
          options: const [
            BracuSelectOption<_RoomFilter>(
              value: _RoomFilter.labs,
              label: 'Labs',
              subtitle: 'Computer and lab rooms',
            ),
            BracuSelectOption<_RoomFilter>(
              value: _RoomFilter.classes,
              label: 'Classes',
              subtitle: 'Regular classrooms',
            ),
            BracuSelectOption<_RoomFilter>(
              value: _RoomFilter.theater,
              label: 'Theaters',
              subtitle: 'Lecture theater rooms',
            ),
          ],
          onSelected: _changeFilter,
        ),
      ],
      body: FutureBuilder<List<_FreeRoomSlot>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              _lastSlots.isEmpty) {
            return buildRefreshLoadingState(
              onRefresh: _refresh,
              label: 'Loading...',
            );
          }

          final slots = snapshot.data ?? _lastSlots;
          final visibleSlots = _visibleRoomSlots(slots);
          if (visibleSlots.isEmpty) {
            if (_shouldOfferNextDayLabs()) {
              return _buildAfterHoursPromptState();
            }
            return buildRefreshEmptyState(
              onRefresh: _refresh,
              message: _dynamicEmptyMessage(),
            );
          }

          final highlightIndex = _highlightIndex(visibleSlots);
          final highlightedSlot = highlightIndex == null
              ? null
              : visibleSlots[highlightIndex];
          final highlightToken = highlightedSlot == null
              ? null
              : '${highlightedSlot.roomNumber}_${highlightedSlot.startTime}_${highlightedSlot.endTime}';
          final groupedSlots = <String, List<_FreeRoomSlot>>{};
          for (final slot in visibleSlots) {
            final key = '${slot.startTime}|${slot.endTime}';
            groupedSlots.putIfAbsent(key, () => <_FreeRoomSlot>[]).add(slot);
          }
          _highlightKey = null;
          if (highlightToken != null && highlightToken != _lastHighlightToken) {
            _lastHighlightToken = highlightToken;
            _didScroll = false;
            _scrollRetry = false;
          }

          final children = <Widget>[];
          for (final entry in groupedSlots.entries) {
            final timeSlots = entry.value;
            final firstSlot = timeSlots.first;
            children.add(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: BracuSectionTitle(
                          title: formatTimeRange(
                            firstSlot.startTime,
                            firstSlot.endTime,
                          ),
                        ),
                      ),
                      Text(
                        _headerDayLabel(),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: BracuPalette.textPrimary(context),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ...timeSlots.map((slot) {
                    final slotToken =
                        '${slot.roomNumber}_${slot.startTime}_${slot.endTime}';
                    final isHighlighted = slotToken == highlightToken;
                    if (isHighlighted) {
                      _highlightKey ??= GlobalKey();
                    }
                    final roomSlots = visibleSlots
                        .where((item) => item.roomNumber == slot.roomNumber)
                        .toList();
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: () => _showRoomDetails(slot, roomSlots),
                        child: BracuCard(
                          key: isHighlighted ? _highlightKey : null,
                          isHighlighted: false,
                          highlightColor: _roomCardHighlightColor(slot),
                          backgroundColor: _roomCardBackgroundColor(slot),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 7,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text.rich(
                                      TextSpan(
                                        children: [
                                          TextSpan(
                                            text: slot.roomNumber,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          if (slot.statusLabel == 'Available')
                                            TextSpan(
                                              text: ' Free',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w600,
                                                color:
                                                    BracuPalette.textSecondary(
                                                      context,
                                                    ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      formatTimeRange(
                                        slot.startTime,
                                        slot.endTime,
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
                                    Text.rich(
                                      _roomProgramLabelSpan(slot),
                                      textAlign: TextAlign.right,
                                    ),
                                    if (slot.statusLabel.isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        slot.statusLabel,
                                        textAlign: TextAlign.right,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: BracuPalette.textSecondary(
                                            context,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 6),
                ],
              ),
            );
          }

          if (!_didScroll && _highlightKey != null) {
            _attemptScrollToHighlight();
          }

          return BracuRefreshList(
            onRefresh: _refresh,
            controller: _scrollController,
            children: children,
          );
        },
      ),
    );
  }

  int? _highlightIndex(List<_FreeRoomSlot> slots) {
    if (slots.isEmpty) return null;
    final nowMinutes = _minutesOfDay(TimeOfDay.now());
    for (var i = 0; i < slots.length; i++) {
      final slot = slots[i];
      final start = _minutesFromString(slot.startTime);
      final end = _minutesFromString(slot.endTime);
      if (start != null &&
          end != null &&
          nowMinutes >= start &&
          nowMinutes < end) {
        return i;
      }
    }
    for (var i = 0; i < slots.length; i++) {
      final start = _minutesFromString(slots[i].startTime);
      if (start != null && nowMinutes < start) return i;
    }
    return 0;
  }

  List<_FreeRoomSlot> _buildFreeRoomSlots(
    List<SeatStatusDetailsResponse> details,
    String day,
  ) {
    final grouped = <String, _RoomSeed>{};
    final seenBusyKeys = <String>{};

    for (final detailsEntry in details) {
      for (final section in _extractRoomSections(detailsEntry)) {
        final roomNumber = section.roomNumber.trim();
        if (roomNumber.isEmpty) continue;
        final room = grouped.putIfAbsent(
          roomNumber,
          () => _RoomSeed(
            roomNumber: roomNumber,
            roomName: section.roomName.trim(),
          ),
        );
        final courseCode = section.courseCode.trim().toUpperCase();
        if (courseCode.isNotEmpty) {
          final program = _courseProgramCode(courseCode);
          if (program.isNotEmpty) {
            room.programCounts[program] =
                (room.programCounts[program] ?? 0) + 1;
          }
        }
        final courseTitle = section.name.trim();
        if (courseTitle.isNotEmpty && courseCode.isNotEmpty) {
          room.courseTitles.add('$courseTitle ($courseCode)');
        } else if (courseTitle.isNotEmpty) {
          room.courseTitles.add(courseTitle);
        } else {
          final sectionName = section.sectionName.trim();
          final fallback = sectionName.isEmpty
              ? courseCode
              : '$courseCode - $sectionName';
          if (fallback.trim().isNotEmpty) {
            room.courseTitles.add(fallback.trim());
          }
        }
        for (final slot in section.sectionSchedule.classSchedules) {
          if (_normalizeDay(slot.day) != day) continue;
          final key =
              '$roomNumber|${slot.day}|${slot.startTime}|${slot.endTime}';
          if (!seenBusyKeys.add(key)) continue;
          room.busySlots.add(
            _TimeSlot.fromStrings(
              startTime: slot.startTime,
              endTime: slot.endTime,
            ),
          );
        }
      }
    }

    final slots = <_FreeRoomSlot>[];
    for (final room in grouped.values) {
      final freeSlots = _freeWithinDay(_mergeSlots(room.busySlots));
      for (final free in freeSlots) {
        slots.add(
          _FreeRoomSlot(
            roomNumber: room.roomNumber,
            roomName: room.roomName.isEmpty ? 'Room' : room.roomName,
            courseTitlesLabel: (room.courseTitles.toList()..sort()).join(', '),
            dominantProgramCode: _dominantProgramCode(room),
            startTime: _formatTimeOfDay(free.start),
            endTime: _formatTimeOfDay(free.end),
            statusLabel: _statusLabel(free.start, free.end),
          ),
        );
      }
    }

    slots.sort((a, b) {
      final startCompare = (_minutesFromString(a.startTime) ?? 0).compareTo(
        _minutesFromString(b.startTime) ?? 0,
      );
      if (startCompare != 0) return startCompare;
      return a.roomNumber.compareTo(b.roomNumber);
    });
    return slots;
  }

  List<_FreeRoomSlot> _applySelectedFilter(List<_FreeRoomSlot> slots) {
    return _applyFilter(slots, _selectedFilter);
  }

  List<_FreeRoomSlot> _applyFilter(
    List<_FreeRoomSlot> slots,
    _RoomFilter filter,
  ) {
    return slots
        .where((slot) => _matchesFilter(slot.roomNumber, filter))
        .toList();
  }

  List<SeatStatusSection> _extractRoomSections(
    SeatStatusDetailsResponse details,
  ) {
    final sections = <SeatStatusSection>[];
    final child = details.childSection;
    if (child != null && _looksLikeRoomSection(child)) {
      sections.add(child);
    }
    final main = details.section;
    if (_looksLikeRoomSection(main)) {
      sections.add(main);
    }
    return sections;
  }

  bool _looksLikeRoomSection(SeatStatusSection section) {
    return section.roomNumber.trim().isNotEmpty ||
        section.roomName.trim().isNotEmpty;
  }

  String _normalizeDay(String value) {
    final trimmed = value.trim().toLowerCase();
    if (trimmed.isEmpty) return '';
    return trimmed[0].toUpperCase() + trimmed.substring(1);
  }

  List<_TimeSlot> _mergeSlots(List<_TimeSlot> slots) {
    if (slots.isEmpty) return const <_TimeSlot>[];
    final sorted = [
      ...slots,
    ]..sort((a, b) => _minutesOfDay(a.start).compareTo(_minutesOfDay(b.start)));
    final merged = <_TimeSlot>[];
    for (final slot in sorted) {
      if (merged.isEmpty) {
        merged.add(slot);
        continue;
      }
      final last = merged.last;
      if (_minutesOfDay(slot.start) <= _minutesOfDay(last.end)) {
        if (_minutesOfDay(slot.end) > _minutesOfDay(last.end)) {
          merged[merged.length - 1] = _TimeSlot(
            start: last.start,
            end: slot.end,
          );
        }
      } else {
        merged.add(slot);
      }
    }
    return merged;
  }

  List<_TimeSlot> _freeWithinDay(List<_TimeSlot> busy) {
    const dayStart = TimeOfDay(hour: 8, minute: 0);
    const dayEnd = TimeOfDay(hour: 20, minute: 0);
    if (busy.isEmpty) {
      return const <_TimeSlot>[_TimeSlot(start: dayStart, end: dayEnd)];
    }
    final free = <_TimeSlot>[];
    var current = dayStart;
    for (final slot in busy) {
      if (_minutesOfDay(current) < _minutesOfDay(slot.start)) {
        free.add(_TimeSlot(start: current, end: slot.start));
      }
      if (_minutesOfDay(slot.end) > _minutesOfDay(current)) {
        current = slot.end;
      }
    }
    if (_minutesOfDay(current) < _minutesOfDay(dayEnd)) {
      free.add(_TimeSlot(start: current, end: dayEnd));
    }
    return free
        .where((slot) => _minutesOfDay(slot.start) < _minutesOfDay(slot.end))
        .toList();
  }

  String _statusLabel(TimeOfDay start, TimeOfDay end) {
    if (_isViewingFutureDate()) {
      return 'Upcoming';
    }
    final nowMinutes = _minutesOfDay(TimeOfDay.now());
    final startMinutes = _minutesOfDay(start);
    final endMinutes = _minutesOfDay(end);
    if (nowMinutes >= startMinutes && nowMinutes < endMinutes) {
      return 'Available';
    }
    if (nowMinutes < startMinutes) {
      return 'Upcoming';
    }
    return '';
  }

  int _minutesOfDay(TimeOfDay time) => time.hour * 60 + time.minute;

  int? _minutesFromString(String value) => BracuTime.toMinutes(value);

  String _todayCacheLabel() {
    final display = _activeDate;
    return '${display.year}-${display.month.toString().padLeft(2, '0')}-${display.day.toString().padLeft(2, '0')}';
  }

  Future<List<_FreeRoomSlot>> _readCachedSlots() async {
    try {
      final cached = await SeatStatusService().loadCachedFreeLabsSlots(
        dateKey: _todayCacheLabel(),
      );
      return cached.map(_FreeRoomSlot.fromJson).toList();
    } catch (_) {
      return const <_FreeRoomSlot>[];
    }
  }

  Future<void> _writeCachedSlots(List<_FreeRoomSlot> slots) async {
    try {
      await SeatStatusService().saveFreeLabsSlotsCacheIfChanged(
        dateKey: _todayCacheLabel(),
        slots: slots.map((slot) => slot.toJson()).toList(),
      );
    } catch (_) {}
  }

  String _headerDayLabel() {
    final display = _activeDate;
    return '${formatWeekdayTitle(_activeDayName)}, ${display.day} ${_monthLabel(display.month)}';
  }

  String _monthLabel(int month) {
    const months = <String>[
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    if (month < 1 || month > 12) return '';
    return months[month - 1];
  }

  Future<void> _showNextDayLabs() async {
    final next = _loadSlots();
    setState(() {
      _showNextDayAfterHours = true;
      _future = next;
      _didScroll = false;
      _scrollRetry = false;
    });
    final slots = await next;
    if (!mounted) return;
    setState(() {
      _lastSlots = slots;
    });
  }

  Widget _buildAfterHoursPromptState() {
    final nextDate = _nextLabsDate();
    final nextDay = formatWeekdayTitle(DateFormat('EEEE').format(nextDate));
    final nextDateLabel =
        '$nextDay, ${nextDate.day} ${_monthLabel(nextDate.month)}';
    return BracuRefreshList(
      onRefresh: _refresh,
      controller: _scrollController,
      children: [
        const SizedBox(height: 160),
        BracuCard(
          backgroundColor: Colors.transparent,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                'Today\'s lab hours are over.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: BracuPalette.textPrimary(context),
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Show next day labs for $nextDateLabel?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: BracuPalette.textSecondary(context),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: _showNextDayLabs,
                icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                label: const Text('Show Next Day Labs'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _showRoomDetails(
    _FreeRoomSlot slot,
    List<_FreeRoomSlot> roomSlots,
  ) async {
    final visibleRoomSlots = _visibleRoomSlots(roomSlots);
    await showBracuBottomSheet<void>(
      context,
      title: '${slot.roomNumber} • ${_roomTypeLabel(slot.roomNumber)}',
      subtitle: _roomHeaderSubtitle(slot),
      builder: (sheetContext, textPrimary, textSecondary) {
        return ListView(
          shrinkWrap: true,
          children: [
            Text(
              _roomTimelineLabel(),
              style: TextStyle(
                color: textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            ...visibleRoomSlots.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: BracuCard(
                  isHighlighted: false,
                  highlightColor: BracuPalette.primary,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          formatTimeRange(item.startTime, item.endTime),
                          style: TextStyle(
                            color: textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (item.statusLabel.isNotEmpty)
                        Text(
                          item.statusLabel,
                          style: TextStyle(
                            color: textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  List<_FreeRoomSlot> _visibleRoomSlots(List<_FreeRoomSlot> roomSlots) {
    if (_isViewingFutureDate()) {
      return roomSlots;
    }
    final nowMinutes = _minutesOfDay(TimeOfDay.now());
    return roomSlots.where((item) {
      final end = _minutesFromString(item.endTime);
      return end != null && end > nowMinutes;
    }).toList();
  }

  bool _matchesFilter(String roomNumber, [_RoomFilter? filter]) {
    final suffix = roomNumber.trim().toUpperCase();
    return switch (filter ?? _selectedFilter) {
      _RoomFilter.classes => suffix.endsWith('C'),
      _RoomFilter.labs => suffix.endsWith('L'),
      _RoomFilter.theater => suffix.endsWith('T'),
    };
  }

  String _formatTimeOfDay(TimeOfDay time) {
    final normalizedHour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final minute = time.minute.toString().padLeft(2, '0');
    final suffix = time.period == DayPeriod.am ? 'AM' : 'PM';
    return '$normalizedHour:$minute $suffix';
  }

  String _roomHeaderSubtitle(_FreeRoomSlot slot) {
    final parts = <String>[];
    final roomName = slot.roomName.trim();
    if (roomName.isNotEmpty && roomName != slot.roomNumber.trim()) {
      parts.add(roomName);
    }
    final courses = slot.courseTitlesLabel.trim();
    if (courses.isNotEmpty) {
      parts.add(courses);
    }
    return parts.join(' • ');
  }

  String _roomTimelineLabel() {
    if (_isViewingFutureDate()) {
      return formatWeekdayTitle(_activeDayName);
    }
    return 'Today';
  }

  String _roomProgramLabel(_FreeRoomSlot slot) {
    final program = slot.dominantProgramCode.trim().toUpperCase();
    if (program.isEmpty) {
      return slot.roomName;
    }
    return program;
  }

  bool _isGreenProgram(_FreeRoomSlot slot) {
    final program = slot.dominantProgramCode.trim().toUpperCase();
    final roomNumber = slot.roomNumber.trim().toUpperCase();
    final isLab = roomNumber.endsWith('L');
    return isLab && (program == 'CSE' || program == 'EEE');
  }

  String _dominantProgramCode(_RoomSeed room) {
    if (room.programCounts.isEmpty) return '';
    final sorted = room.programCounts.entries.toList()
      ..sort((a, b) {
        final countCompare = b.value.compareTo(a.value);
        if (countCompare != 0) return countCompare;
        return a.key.compareTo(b.key);
      });
    return sorted.first.key;
  }

  Color _roomCardHighlightColor(_FreeRoomSlot slot) {
    return _isGreenProgram(slot)
        ? const Color(0xFF22C55E)
        : BracuPalette.primary;
  }

  Color? _roomCardBackgroundColor(_FreeRoomSlot slot) {
    return null;
  }

  TextSpan _roomProgramLabelSpan(_FreeRoomSlot slot) {
    final program = _roomProgramLabel(slot);
    final roomType = _roomTypeShortLabel(slot.roomNumber);
    return TextSpan(
      children: [
        TextSpan(
          text: program,
          style: TextStyle(
            color: BracuPalette.textPrimary(context),
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (program != slot.roomName && roomType.isNotEmpty)
          TextSpan(
            text: ' $roomType',
            style: TextStyle(
              color: BracuPalette.textSecondary(context),
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
      ],
    );
  }

  String _courseProgramCode(String courseCode) {
    final match = RegExp(
      r'^[A-Z]+',
    ).firstMatch(courseCode.trim().toUpperCase());
    return match?.group(0) ?? '';
  }

  String _roomTypeLabel(String roomNumber) {
    final suffix = roomNumber.trim().toUpperCase();
    if (suffix.endsWith('L')) return 'Lab Room';
    if (suffix.endsWith('T')) return 'Theater Room';
    if (suffix.endsWith('C')) return 'Class Room';
    return 'Room';
  }

  String _roomTypeShortLabel(String roomNumber) {
    final suffix = roomNumber.trim().toUpperCase();
    if (suffix.endsWith('L')) return 'Lab';
    if (suffix.endsWith('T')) return 'Theater';
    if (suffix.endsWith('C')) return 'Class';
    return '';
  }
}

class _FreeRoomSlot {
  const _FreeRoomSlot({
    required this.roomNumber,
    required this.roomName,
    required this.courseTitlesLabel,
    required this.dominantProgramCode,
    required this.startTime,
    required this.endTime,
    required this.statusLabel,
  });

  factory _FreeRoomSlot.fromJson(Map<String, dynamic> json) {
    return _FreeRoomSlot(
      roomNumber: (json['roomNumber'] as String? ?? '').trim(),
      roomName: (json['roomName'] as String? ?? '').trim(),
      courseTitlesLabel: (json['courseTitlesLabel'] as String? ?? '').trim(),
      dominantProgramCode: (json['dominantProgramCode'] as String? ?? '')
          .trim(),
      startTime: (json['startTime'] as String? ?? '').trim(),
      endTime: (json['endTime'] as String? ?? '').trim(),
      statusLabel: (json['statusLabel'] as String? ?? '').trim(),
    );
  }

  final String roomNumber;
  final String roomName;
  final String courseTitlesLabel;
  final String dominantProgramCode;
  final String startTime;
  final String endTime;
  final String statusLabel;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'roomNumber': roomNumber,
      'roomName': roomName,
      'courseTitlesLabel': courseTitlesLabel,
      'dominantProgramCode': dominantProgramCode,
      'startTime': startTime,
      'endTime': endTime,
      'statusLabel': statusLabel,
    };
  }
}

class _RoomSeed {
  _RoomSeed({required this.roomNumber, required this.roomName});

  final String roomNumber;
  final String roomName;
  final Map<String, int> programCounts = <String, int>{};
  final List<_TimeSlot> busySlots = <_TimeSlot>[];
  final Set<String> courseTitles = <String>{};
}

class _TimeSlot {
  const _TimeSlot({required this.start, required this.end});

  _TimeSlot.fromStrings({required String startTime, required String endTime})
    : start = _FreeRoomTime.parse(startTime),
      end = _FreeRoomTime.parse(endTime);

  final TimeOfDay start;
  final TimeOfDay end;
}

class _FreeRoomTime {
  static TimeOfDay parse(String value) {
    final parsed = BracuTime.parseTime(value);
    if (parsed != null) {
      return TimeOfDay(hour: parsed.hour, minute: parsed.minute);
    }
    return const TimeOfDay(hour: 0, minute: 0);
  }
}

enum _RoomFilter {
  classes('Classes'),
  labs('Labs'),
  theater('Theaters');

  const _RoomFilter(this.label);

  final String label;
}
