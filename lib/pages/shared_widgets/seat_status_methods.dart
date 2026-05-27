// ignore_for_file: invalid_use_of_protected_member

part of 'package:preconnect/pages/seat_status.dart';

class SeatTimetable {
  final String startTime;
  final String endTime;

  const SeatTimetable({required this.startTime, required this.endTime});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SeatTimetable &&
          startTime == other.startTime &&
          endTime == other.endTime;

  @override
  int get hashCode => Object.hash(startTime, endTime);

  String get repr => "${formatTime(startTime)} - ${formatTime(endTime)}";
}

extension _SeatStatusPageStateMethods on _SeatStatusPageState {
  _SeatStatusCardData _buildCardFromDetails({
    required int sectionId,
    required SeatStatusDetailsResponse details,
  }) {
    final total = details.capacity;
    final resolvedRemaining = total - details.consumedSeat;
    final resolvedConsumed = details.consumedSeat;
    final facultySummaryLabel = seatStatusFacultySummaryLabel(details.faculty);
    final facultyDetailLabel = seatStatusFacultyDetailLabel(details.faculty);
    final facultySearchText = seatStatusFacultySearchText(details.faculty);
    final timetables = details.sectionSchedule.classSchedules
        .map(
          (data) =>
              SeatTimetable(startTime: data.startTime, endTime: data.endTime),
        )
        .toList();

    return _SeatStatusCardData(
      sectionId: sectionId,
      courseCode: details.courseCode,
      sectionName: details.sectionName,
      courseName: details.courseName,
      faculty: details.faculty,
      facultyInitial: facultySummaryLabel,
      facultyMeta: facultyDetailLabel,
      credits: details.courseCredit,
      room: details.roomNumber,
      courseType: details.courseType,
      classSchedule: details.sectionSchedule.classSchedules,
      labSchedule: details.labSchedules,
      labRoom: details.labRoomName ?? '',
      labCourseCode: details.labCourseCode ?? '',
      labName: details.labName ?? '',
      labFaculties: details.labFaculties ?? '',
      labSectionId: details.labSectionId,
      midExamDate: details.sectionSchedule.midExamDate,
      midExamStartTime: details.sectionSchedule.midExamStartTime,
      midExamEndTime: details.sectionSchedule.midExamEndTime,
      finalExamDate: details.sectionSchedule.finalExamDate,
      finalExamStartTime: details.sectionSchedule.finalExamStartTime,
      finalExamEndTime: details.sectionSchedule.finalExamEndTime,
      timetables: timetables,
      remaining: resolvedRemaining,
      consumed: resolvedConsumed,
      total: total,
      searchToken: _buildSearchToken(
        sectionId: sectionId,
        courseCode: details.courseCode,
        sectionName: details.sectionName,
        courseName: details.courseName,
        facultySearchText: facultySearchText,
        room: details.roomNumber,
        courseType: details.courseType,
        labRoom: details.labRoomName ?? '',
        classSchedule: details.sectionSchedule.classSchedules,
        labSchedule: details.labSchedules,
        midExamDate: details.sectionSchedule.midExamDate,
        midExamStartTime: details.sectionSchedule.midExamStartTime,
        midExamEndTime: details.sectionSchedule.midExamEndTime,
        finalExamDate: details.sectionSchedule.finalExamDate,
        finalExamStartTime: details.sectionSchedule.finalExamStartTime,
        finalExamEndTime: details.sectionSchedule.finalExamEndTime,
        total: total,
        consumed: resolvedConsumed,
        remaining: resolvedRemaining,
        sectionType: details.sectionType,
        academicDegree: details.academicDegree,
        semesterSessionId: details.semesterSessionId,
        parentSectionId: details.parentSectionId,
        courseId: details.courseId,
        roomName: details.roomName,
        labCourseCode: details.labCourseCode ?? '',
        labName: details.labName ?? '',
        labFaculties: details.labFaculties ?? '',
        labSectionId: details.labSectionId,
      ),
    );
  }

  String _buildSearchToken({
    required int sectionId,
    required String courseCode,
    required String sectionName,
    required String courseName,
    required String facultySearchText,
    required String room,
    required String courseType,
    required String labRoom,
    required String sectionType,
    required String academicDegree,
    required int semesterSessionId,
    required int? parentSectionId,
    required int courseId,
    required String roomName,
    required String labCourseCode,
    required String labName,
    required String labFaculties,
    required int? labSectionId,
    required List<SeatStatusClassSchedule> classSchedule,
    required List<SeatStatusClassSchedule> labSchedule,
    required String? midExamDate,
    required String? midExamStartTime,
    required String? midExamEndTime,
    required String? finalExamDate,
    required String? finalExamStartTime,
    required String? finalExamEndTime,
    required int total,
    required int consumed,
    required int remaining,
  }) {
    final scheduleToken = _buildScheduleSearchToken(classSchedule, labSchedule);
    final examToken =
        '${midExamDate ?? ''} ${midExamStartTime ?? ''} ${midExamEndTime ?? ''} '
        '${finalExamDate ?? ''} ${finalExamStartTime ?? ''} ${finalExamEndTime ?? ''}';
    return '$courseCode $sectionName $courseName '
            '$facultySearchText '
            '$room $roomName $labRoom $labCourseCode $labName $labFaculties '
            '$sectionId $courseId $semesterSessionId $parentSectionId $labSectionId '
            '$courseType $sectionType $academicDegree '
            '$total $consumed $remaining '
            '$scheduleToken $examToken'
        .toLowerCase();
  }

  String _buildScheduleSearchToken(
    List<SeatStatusClassSchedule> classSchedule,
    List<SeatStatusClassSchedule> labSchedule,
  ) {
    final chunks = <String>[];
    for (final item in <SeatStatusClassSchedule>[
      ...classSchedule,
      ...labSchedule,
    ]) {
      final dayRaw = item.day.trim();
      final dayPretty = formatWeekdayTitle(item.day);
      final startRaw = item.startTime.trim();
      final endRaw = item.endTime.trim();
      chunks.add('$dayRaw $dayPretty $startRaw $endRaw');
    }
    return chunks.join(' ');
  }

  Widget _buildPageContent(BuildContext context) {
    final hasCards = _cards.isNotEmpty;
    final hasVisibleCards = _visibleCards.isNotEmpty;
    final itemCount = hasVisibleCards ? _visibleCards.length + 1 : 1;

    return BracuPageScaffold(
      title: 'Seat',
      subtitle: 'Status',
      icon: Icons.insights_outlined,
      actions: [
        BracuNotificationsIconButton(
          onTap: () async {
            await Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const NotificationsPage(),
              ),
            );
          },
          iconSize: 24,
          padding: 8,
        ),
      ],
      body: Stack(
        children: [
          if (_isInitialLoading && !hasCards)
            const Center(child: BracuLoading())
          else
            BracuRefreshListBuilder(
              onRefresh: _refreshDetailsFromApi,
              itemCount: itemCount,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return _buildFilterHeader(context);
                }
                if (!hasCards || !hasVisibleCards) {
                  return const SizedBox.shrink();
                }
                final item = _visibleCards[index - 1];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _SeatStatusCard(
                    item: item,
                    onTap: () => _openCourseCommunitySheet(item),
                    onPinTap: () => _togglePin(item.sectionId),
                    pinned: _isPinnedSection(item.sectionId),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildFilterHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _buildSearchField(context),
          const SizedBox(height: 10),
          _buildFilterActions(context),
        ],
      ),
    );
  }

  Widget _buildSearchField(BuildContext context) {
    return BracuSearchField(
      controller: _searchController,
      hintText: 'Search by anything...',
      query: _searchQuery,
      keySuffix: 'seat',
    );
  }

  Widget _buildFilterActions(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: [
          _buildAvailabilityFilterAction(),
          _buildDayFilterAction(context),
          _buildTimeFilterAction(context),
        ],
      ),
    );
  }

  Widget _buildAvailabilityFilterAction() {
    return _FilterChip(
      icon: Icons.event_available_outlined,
      label: 'Available',
      selected: _availableOnly,
      onTap: () => _setAvailableFilter(!_availableOnly),
      showArrow: false,
    );
  }

  Widget _buildDayFilterAction(BuildContext context) {
    final label = _selectedDayFilter.isEmpty
        ? 'Any Day'
        : formatWeekdayTitle(_selectedDayFilter);
    return BracuSelectDropdownChip<String>(
      icon: Icons.calendar_today_outlined,
      label: label,
      selected: _selectedDayFilter.isNotEmpty,
      compact: true,
      borderRadius: 999,
      title: 'Filter by Day',
      subtitle: 'Show seat status for a specific weekday',
      selectedValue: _selectedDayFilter,
      options: <BracuSelectOption<String>>[
        const BracuSelectOption<String>(
          value: '',
          label: 'Any Day',
          icon: Icons.all_inclusive_rounded,
          subtitle: 'Everyday',
        ),
        ..._SeatStatusPageState._weekdayOrder.map(
          (day) => BracuSelectOption<String>(
            value: day,
            label: formatWeekdayTitle(day),
            icon: Icons.calendar_today_outlined,
            subtitle: 'Only ${formatWeekdayTitle(day)}',
          ),
        ),
      ],
      onSelected: _setDayFilter,
    );
  }

  Widget _buildTimeFilterAction(BuildContext context) {
    final label = _selectedTimeFilter.isEmpty
        ? 'Any Time'
        : formatWeekdayTitle(_selectedTimeFilter);

    final assortedTimes =
        _cards.expand((card) => card.timetables).toSet().toList()..sort((a, b) {
          final startA = BracuTime.toMinutes(a.startTime) ?? 24 * 60;
          final startB = BracuTime.toMinutes(b.startTime) ?? 24 * 60;
          final startCmp = startA.compareTo(startB);
          if (startCmp != 0) return startCmp;

          final endA = BracuTime.toMinutes(a.endTime) ?? 24 * 60;
          final endB = BracuTime.toMinutes(b.endTime) ?? 24 * 60;
          return endA.compareTo(endB);
        });

    return BracuSelectDropdownChip<String>(
      icon: Icons.calendar_today_outlined,
      label: label,
      selected: _selectedTimeFilter.isNotEmpty,
      compact: true,
      borderRadius: 999,
      title: 'Filter by Time',
      subtitle: 'Show seat status for a specific time',
      selectedValue: _selectedTimeFilter,
      options: <BracuSelectOption<String>>[
        const BracuSelectOption<String>(
          value: '',
          label: 'Any Time',
          icon: Icons.all_inclusive_rounded,
          subtitle: 'Possible times',
        ),
        ...assortedTimes.map(
          (data) => BracuSelectOption<String>(
            value: data.repr,
            label: data.repr,
            icon: Icons.calendar_today_outlined,
            subtitle: 'Only ${data.repr}',
          ),
        ),
      ],
      onSelected: _setTimeFilter,
    );
  }

  void _setAvailableFilter(bool next) {
    if (next == _availableOnly) return;
    _refreshVisibleCards(availableOnly: next);
  }

  void _setDayFilter(String next) {
    if (next == _selectedDayFilter) return;
    _refreshVisibleCards(dayFilter: next, timeFilter: _selectedTimeFilter);
  }

  void _setTimeFilter(String next) {
    if (next == _selectedTimeFilter) return;
    _refreshVisibleCards(dayFilter: _selectedDayFilter, timeFilter: next);
  }

  void _refreshVisibleCards({
    bool? availableOnly,
    String? dayFilter,
    String? timeFilter,
    String? query,
  }) {
    final resolvedAvailableOnly = availableOnly ?? _availableOnly;
    final resolvedDayFilter = dayFilter ?? _selectedDayFilter;
    final resolvedTimeFilter = timeFilter ?? _selectedTimeFilter;
    final resolvedQuery = query ?? _searchQuery;
    final nextVisible = _filterCards(
      _cards,
      resolvedQuery,
      availableOnly: resolvedAvailableOnly,
      dayFilter: resolvedDayFilter,
      timeFilter: resolvedTimeFilter,
    );
    final filtersChanged =
        resolvedAvailableOnly != _availableOnly ||
        resolvedDayFilter != _selectedDayFilter ||
        resolvedTimeFilter != _selectedTimeFilter ||
        resolvedQuery != _searchQuery;
    if (!filtersChanged &&
        !_areCardListsDifferent(_visibleCards, nextVisible)) {
      return;
    }
    setState(() {
      _availableOnly = resolvedAvailableOnly;
      _selectedDayFilter = resolvedDayFilter;
      _selectedTimeFilter = resolvedTimeFilter;
      _searchQuery = resolvedQuery;
      _visibleCards
        ..clear()
        ..addAll(nextVisible);
    });
    _updatePollingStrategy();
  }

  List<_SeatStatusCardData> _filterCards(
    List<_SeatStatusCardData> source,
    String query, {
    required bool availableOnly,
    required String dayFilter,
    required String timeFilter,
  }) {
    final q = query.trim().toLowerCase();
    return source.where((card) {
      if (q.isNotEmpty && !card.searchToken.contains(q)) return false;
      if (availableOnly && card.remaining <= 0) return false;
      if (dayFilter.isNotEmpty) {
        final schedules = <SeatStatusClassSchedule>[
          ...card.classSchedule,
          ...card.labSchedule,
        ];
        final hasDay = schedules.any(
          (entry) => normalizeWeekday(entry.day) == dayFilter,
        );
        if (!hasDay) return false;
      }
      if (timeFilter.isNotEmpty) {
        final hasTime = card.timetables.any((data) => data.repr == timeFilter);

        if (!hasTime) return false;
      }
      return true;
    }).toList();
  }

  void _updateSearchQuery(String nextQuery) {
    if (nextQuery == _searchQuery) return;
    _refreshVisibleCards(query: nextQuery);
  }

  void _applyCardsSnapshot(
    List<_SeatStatusCardData> nextCards, {
    bool? isInitialLoading,
  }) {
    final nextVisible = _filterCards(
      nextCards,
      _searchQuery,
      availableOnly: _availableOnly,
      dayFilter: _selectedDayFilter,
      timeFilter: _selectedTimeFilter,
    );
    if (!mounted) return;
    final cardsChanged = _areCardListsDifferent(_cards, nextCards);
    final visibleChanged = _areCardListsDifferent(_visibleCards, nextVisible);
    final loadingChanged =
        isInitialLoading != null && _isInitialLoading != isInitialLoading;
    if (!cardsChanged && !visibleChanged && !loadingChanged) {
      return;
    }
    setState(() {
      _cards
        ..clear()
        ..addAll(nextCards);
      _visibleCards
        ..clear()
        ..addAll(nextVisible);
      if (isInitialLoading != null) {
        _isInitialLoading = isInitialLoading;
      }
    });
    _updatePollingStrategy();
  }

  void _sortCardsByCourseAndSection(List<_SeatStatusCardData> cards) {
    cards.sort((a, b) {
      final ap = _isPinnedSection(a.sectionId) ? 0 : 1;
      final bp = _isPinnedSection(b.sectionId) ? 0 : 1;
      if (ap != bp) return ap.compareTo(bp);
      final codeCmp = a.courseCode.compareTo(b.courseCode);
      if (codeCmp != 0) return codeCmp;
      final sectionCmp = _sectionOrder(
        a.sectionName,
      ).compareTo(_sectionOrder(b.sectionName));
      if (sectionCmp != 0) return sectionCmp;
      return a.sectionName.compareTo(b.sectionName);
    });
  }

  bool _areCardListsDifferent(
    List<_SeatStatusCardData> a,
    List<_SeatStatusCardData> b,
  ) {
    if (identical(a, b)) return false;
    if (a.length != b.length) return true;
    for (var i = 0; i < a.length; i++) {
      if (!_isSameCard(a[i], b[i])) return true;
    }
    return false;
  }

  bool _isSameCard(_SeatStatusCardData x, _SeatStatusCardData y) {
    if (x.sectionId != y.sectionId) return false;
    if (x.courseCode != y.courseCode) return false;
    if (x.sectionName != y.sectionName) return false;
    if (x.courseName != y.courseName) return false;
    if (x.facultyInitial != y.facultyInitial) return false;
    if (x.facultyMeta != y.facultyMeta) return false;
    if (x.credits != y.credits) return false;
    if (x.room != y.room) return false;
    if (x.courseType != y.courseType) return false;
    if (x.labRoom != y.labRoom) return false;
    if (x.labCourseCode != y.labCourseCode) return false;
    if (x.labName != y.labName) return false;
    if (x.labFaculties != y.labFaculties) return false;
    if (x.labSectionId != y.labSectionId) return false;
    if (x.midExamDate != y.midExamDate) return false;
    if (x.midExamStartTime != y.midExamStartTime) return false;
    if (x.midExamEndTime != y.midExamEndTime) return false;
    if (x.finalExamDate != y.finalExamDate) return false;
    if (x.finalExamStartTime != y.finalExamStartTime) return false;
    if (x.finalExamEndTime != y.finalExamEndTime) return false;
    if (x.remaining != y.remaining) return false;
    if (x.consumed != y.consumed) return false;
    if (x.total != y.total) return false;
    if (x.searchToken != y.searchToken) return false;
    if (!_sameSchedules(x.classSchedule, y.classSchedule)) return false;
    if (!_sameSchedules(x.labSchedule, y.labSchedule)) return false;
    return true;
  }

  bool _sameSchedules(
    List<SeatStatusClassSchedule> a,
    List<SeatStatusClassSchedule> b,
  ) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].day != b[i].day) return false;
      if (a[i].startTime != b[i].startTime) return false;
      if (a[i].endTime != b[i].endTime) return false;
    }
    return true;
  }

  int _sectionOrder(String sectionName) {
    final number = RegExp(r'\d+').firstMatch(sectionName)?.group(0);
    if (number == null) return 9999;
    return int.tryParse(number) ?? 9999;
  }

  void _updatePollingStrategy() {
    final shouldPoll =
        mounted &&
        HomeTabRegistry.activeTab.value == HomeTab.seatStatus &&
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.paused &&
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.detached;
    if (shouldPoll) {
      _startPolling();
    } else {
      _stopPolling();
    }
  }

  Future<void> _refreshDetailsFromApi({bool forceRefresh = true}) async {
    if (_pollInFlight || _isDetailsRefreshing) return;
    _pollInFlight = true;
    if (mounted && _cards.isEmpty) {
      setState(() {
        _isDetailsRefreshing = true;
      });
    } else {
      _isDetailsRefreshing = true;
    }
    try {
      final details = await _service.fetchAllSectionsDetailsFromApi(
        forceRefresh: forceRefresh,
      );
      if (details.isNotEmpty) {
        await _applyDetailsUpdate(details);
      }
    } catch (_) {
      if (_isInitialLoading && mounted) {
        setState(() {
          _isInitialLoading = false;
        });
      }
    } finally {
      _pollInFlight = false;
      if (mounted && _cards.isEmpty) {
        setState(() {
          _isDetailsRefreshing = false;
        });
      } else {
        _isDetailsRefreshing = false;
      }
    }
  }

  void _startPolling() {
    if (_pollTimer != null) return;
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted) return;
      if (HomeTabRegistry.activeTab.value != HomeTab.seatStatus) return;
      unawaited(_refreshDetailsFromApi(forceRefresh: true));
    });
    unawaited(_refreshDetailsFromApi(forceRefresh: true));
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  bool _isPinnedSection(int sectionId) {
    return _pinnedSections.contains(sectionId.toString());
  }
}
