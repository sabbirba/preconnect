import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:preconnect/api/seat_status_service.dart';
import 'package:preconnect/pages/free_labs_helpers.dart';
import 'package:preconnect/pages/home_tab.dart';
import 'package:preconnect/pages/ui_kit.dart';

class FreeLabsPage extends StatefulWidget {
  const FreeLabsPage({super.key});

  @override
  State<FreeLabsPage> createState() => _FreeLabsPageState();
}

class _FreeLabsPageState extends State<FreeLabsPage> {
  final FreeLabsRoomBuilder _rooms = const FreeLabsRoomBuilder();
  final ScrollController _scrollController = ScrollController();
  final BracuHighlightScroller _highlightScroller = BracuHighlightScroller();

  late Future<List<FreeRoomSlot>> _future;
  Map<int, SeatStatusDetailsResponse>? _cachedDetails;
  List<FreeRoomSlot>? _latestSlots;
  int _slotsRequestId = 0;
  RoomFilter _selectedFilter = RoomFilter.labs;
  bool _showNextDayAfterHours = false;

  @override
  void initState() {
    super.initState();
    _cachedDetails = SeatStatusService().cachedDetails;
    _latestSlots = _buildCachedSlots();
    _future = _latestSlots == null
        ? _loadSlots()
        : Future<List<FreeRoomSlot>>.value(_latestSlots!);
    _bindSlotsFuture(_future);
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
    setState(() {
      _showNextDayAfterHours = false;
      _highlightScroller.reset();
      _latestSlots = _buildCachedSlots();
      _future = _loadSlots();
    });
    _bindSlotsFuture(_future);
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
    return _displayDate(now: now).isAfter(today);
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

  Future<List<FreeRoomSlot>> _loadSlots({bool forceRefresh = false}) async {
    final allSlots = await _loadAllSlots(forceRefresh: forceRefresh);
    return _applySelectedFilter(allSlots);
  }

  Future<List<FreeRoomSlot>> _loadAllSlots({bool forceRefresh = false}) async {
    final service = SeatStatusService();
    final details = await service.fetchAllSectionsDetailsFromApi(
      forceRefresh: forceRefresh,
    );
    return _rooms.buildSlots(details.values.toList(), day: _activeDayName);
  }

  Future<void> _refresh() async {
    setState(() {
      _highlightScroller.reset();
      _future = _loadSlots(forceRefresh: true);
    });
    _bindSlotsFuture(_future);
  }

  void _attemptScrollToHighlight() {
    _highlightScroller.attempt(
      mounted: mounted,
      rebuild: () => setState(() {}),
    );
  }

  Future<void> _changeFilter(RoomFilter selected) async {
    if (selected == _selectedFilter) return;
    setState(() {
      _selectedFilter = selected;
      _highlightScroller.reset();
      _latestSlots = _buildCachedSlots();
      _future = _loadSlots();
    });
    _bindSlotsFuture(_future);
  }

  String _dynamicHeaderTitle() {
    return switch (_selectedFilter) {
      RoomFilter.labs => 'Free Labs',
      RoomFilter.classes => 'Free Classes',
      RoomFilter.theater => 'Free Theaters',
    };
  }

  String _dynamicEmptyMessage() {
    final weekday = formatWeekdayTitle(_activeDayName);
    return switch (_selectedFilter) {
      RoomFilter.labs => 'No free labs found for $weekday.',
      RoomFilter.classes => 'No free classes found for $weekday.',
      RoomFilter.theater => 'No free theaters found for $weekday.',
    };
  }

  @override
  Widget build(BuildContext context) {
    final cachedSlots = _latestSlots;
    return BracuPageScaffold(
      title: _dynamicHeaderTitle(),
      subtitle: _headerDayLabel(),
      icon: Icons.computer_outlined,
      actions: [
        BracuSelectDropdownChip<RoomFilter>(
          label: _selectedFilter.label,
          title: 'Choose Filter',
          subtitle: 'Filter free labs by room type',
          selectedValue: _selectedFilter,
          options: const [
            BracuSelectOption<RoomFilter>(
              value: RoomFilter.labs,
              label: 'Labs',
              subtitle: 'Computer and lab rooms',
            ),
            BracuSelectOption<RoomFilter>(
              value: RoomFilter.classes,
              label: 'Classes',
              subtitle: 'Regular classrooms',
            ),
            BracuSelectOption<RoomFilter>(
              value: RoomFilter.theater,
              label: 'Theaters',
              subtitle: 'Lecture theater rooms',
            ),
          ],
          onSelected: _changeFilter,
        ),
      ],
      body: FutureBuilder<List<FreeRoomSlot>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError && cachedSlots == null) {
            return buildRefreshErrorState(
              onRefresh: _refresh,
              error: snapshot.error,
            );
          }

          final slots = cachedSlots ?? snapshot.data ?? const <FreeRoomSlot>[];
          if (cachedSlots == null &&
              snapshot.connectionState == ConnectionState.waiting) {
            return buildRefreshLoadingState(onRefresh: _refresh);
          }

          final visibleSlots = _rooms.visibleSlots(
            slots,
            futureDate: _isViewingFutureDate(),
          );
          if (visibleSlots.isEmpty) {
            if (_shouldOfferNextDayLabs()) {
              return _buildAfterHoursPromptState();
            }
            return buildRefreshEmptyState(
              onRefresh: _refresh,
              message: _dynamicEmptyMessage(),
            );
          }

          final highlightIndex = _rooms.highlightIndex(visibleSlots);
          final highlightedSlot = highlightIndex == null
              ? null
              : visibleSlots[highlightIndex];
          final highlightToken = highlightedSlot == null
              ? null
              : '${highlightedSlot.roomNumber}_${highlightedSlot.startTime}_${highlightedSlot.endTime}';
          final groupedSlots = _rooms.groupByTime(visibleSlots);

          _highlightScroller.clearKey();
          _highlightScroller.resetForToken(highlightToken);

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
                      _highlightScroller.ensureKey();
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
                          key: isHighlighted ? _highlightScroller.key : null,
                          isHighlighted: false,
                          highlightColor: _rooms.roomCardHighlightColor(slot),
                          backgroundColor: null,
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

          _attemptScrollToHighlight();
          return BracuRefreshList(
            onRefresh: _refresh,
            controller: _scrollController,
            children: children,
          );
        },
      ),
    );
  }

  List<FreeRoomSlot>? _buildCachedSlots() {
    final details = _cachedDetails;
    if (details == null) return null;
    return _applySelectedFilter(
      _rooms.buildSlots(details.values.toList(), day: _activeDayName),
    );
  }

  List<FreeRoomSlot> _applySelectedFilter(List<FreeRoomSlot> slots) {
    return slots
        .where((slot) => _rooms.matchesFilter(slot.roomNumber, _selectedFilter))
        .toList();
  }

  void _bindSlotsFuture(Future<List<FreeRoomSlot>> future) {
    final requestId = ++_slotsRequestId;
    unawaited(
      future.then((slots) {
        if (!mounted || requestId != _slotsRequestId) return;
        setState(() {
          _cachedDetails = SeatStatusService().cachedDetails;
          _latestSlots = slots;
        });
      }),
    );
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
    setState(() {
      _showNextDayAfterHours = true;
      _highlightScroller.reset();
      _latestSlots = _buildCachedSlots();
      _future = _loadSlots();
    });
    _bindSlotsFuture(_future);
  }

  Widget _buildAfterHoursPromptState() {
    final nextDate = _nextLabsDate();
    final nextDay = formatWeekdayTitle(DateFormat('EEEE').format(nextDate));
    final nextDateLabel =
        '$nextDay, ${nextDate.day} ${_monthLabel(nextDate.month)}';
    return buildRefreshCustomState(
      onRefresh: _refresh,
      topSpacing: 160,
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
          BracuAsyncActionButton(
            onPressed: _showNextDayLabs,
            icon: Icons.arrow_forward_rounded,
            label: 'Show Next Day Labs',
          ),
        ],
      ),
    );
  }

  Future<void> _showRoomDetails(
    FreeRoomSlot slot,
    List<FreeRoomSlot> roomSlots,
  ) async {
    final visibleRoomSlots = _rooms.visibleSlots(
      roomSlots,
      futureDate: _isViewingFutureDate(),
    );
    await showBracuBottomSheet<void>(
      context,
      title: _rooms.displayRoomTitle(slot),
      subtitle: _rooms.roomHeaderSubtitle(slot),
      builder: (sheetContext, textPrimary, textSecondary) {
        return ListView(
          shrinkWrap: true,
          children: [
            Text(
              _rooms.roomTimelineLabel(
                viewingFutureDate: _isViewingFutureDate(),
                activeDayName: _activeDayName,
              ),
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

  String _roomProgramLabel(FreeRoomSlot slot) {
    return _rooms.roomProgramLabel(slot);
  }

  TextSpan _roomProgramLabelSpan(FreeRoomSlot slot) {
    final program = _roomProgramLabel(slot);
    final roomType = _rooms.roomTypeShortLabel(slot.roomNumber);
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
}
