part of 'package:preconnect/pages/seat_status.dart';

extension _SeatStatusPageStateMethods on _SeatStatusPageState {
  Widget _buildPageContent(BuildContext context) {
    final hasCards = _cards.isNotEmpty;
    final listCards = _unplannedCards();
    final hasVisibleCards = listCards.isNotEmpty;
    final showRoutine =
        _selectedArchive.isEmpty &&
        PlannerController.instance.pickedSections.isNotEmpty;
    final cardCount = hasVisibleCards ? listCards.length + 1 : 1;
    final itemCount = cardCount + (showRoutine ? 1 : 0);

    return AppPageScaffold(
      title: 'Seat Status',
      subtitle: _selectedArchive.isEmpty
          ? 'Current'
          : SeatStatusService.archiveSemesterLabel(_selectedArchive),
      icon: Icons.insights_outlined,
      actions: [
        AppSelectDropdownChip<String>(
          title: 'Select Semester',
          label: _selectedArchive.isEmpty
              ? 'Current'
              : SeatStatusService.archiveSemesterLabel(_selectedArchive),
          selected: _selectedArchive.isNotEmpty,
          selectedValue: _selectedArchive,
          compact: true,
          showBorder: false,
          options: [
            const AppSelectOption<String>(
              value: '',
              label: 'Current',
              icon: Icons.calendar_month_rounded,
            ),
            for (final semester in _archiveSemesters)
              AppSelectOption<String>(
                value: semester,
                label: SeatStatusService.archiveSemesterLabel(semester),
                icon: Icons.calendar_month_rounded,
              ),
          ],
          onSelected: (value) {
            if (mounted) _selectArchive(value);
          },
        ),
        AppRefreshButton(
          onPressed: () => unawaited(_refreshFromButton()),
          isLoading: _isDetailsRefreshing,
        ),
      ],
      body: Stack(
        children: [
          if (_isInitialLoading && !hasCards)
            const Center(child: AppLoading())
          else
            AppRefreshListBuilder(
              onRefresh: () async {
                await Future.wait([
                  _loadArchiveSemesters(),
                  _refreshDetailsFromApi(forceRefresh: true),
                ]);
              },
              itemCount: itemCount,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildFilterHeader(context),
                      if (_selectedArchive.isEmpty) ..._plannedSeatCards(),
                    ],
                  );
                }
                if (index >= cardCount) return const SizedBox(height: 64);
                if (!hasCards || !hasVisibleCards) {
                  return const SizedBox.shrink();
                }
                return _seatCard(listCards[index - 1]);
              },
            ),
          if (_selectedArchive.isEmpty) _routineButton(context),
        ],
      ),
    );
  }

  Widget _routineButton(BuildContext context) {
    final picked = PlannerController.instance.pickedSections;
    if (picked.isEmpty) return const SizedBox.shrink();
    final textPrimary = AppPalette.textPrimary(context);
    return Positioned(
      left: 0,
      right: 0,
      bottom: 20,
      child: Center(
        child: Material(
          color: AppPalette.card(context),
          elevation: 6,
          shape: StadiumBorder(
            side: BorderSide(color: AppPalette.accent.withValues(alpha: 0.6)),
          ),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: () => showRoutineSheet(
              context,
              sections: picked,
              clashingIds: _plannedClashIds(picked),
              isRamadan: _isRamadan,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.calendar_month_rounded,
                    size: 18,
                    color: AppPalette.accent,
                  ),
                  const Gap(8),
                  Text(
                    'Schedule',
                    style: TextStyle(
                      color: textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Gap(8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppPalette.accent.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${picked.length}',
                      style: TextStyle(
                        color: textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Set<int> _plannedClashIds(List<SeatStatusDetailsResponse> picked) {
    final conflicts = _conflictIds();
    return {
      for (final section in picked)
        if (conflicts.contains(section.sectionId)) section.sectionId,
    };
  }

  List<SeatCardData> _unplannedCards() {
    if (_selectedArchive.isNotEmpty) return _visibleCards;
    final plannedIds = {
      for (final section in PlannerController.instance.pickedSections)
        section.sectionId,
    };
    final conflicts = _hideConflicts ? _conflictIds() : const <int>{};
    final cards = [
      for (final card in _visibleCards)
        if (!plannedIds.contains(card.sectionId) &&
            !conflicts.contains(card.sectionId))
          card,
    ];
    if (_updateSort.isNotEmpty) {
      _sortByUpdate(cards, latest: _updateSort == 'Latest');
    }
    return cards;
  }

  void _sortByUpdate(List<SeatCardData> cards, {required bool latest}) {
    final missing = latest ? 0 : 1 << 62;
    int stamp(SeatCardData card) =>
        card.lastUpdatedAt?.millisecondsSinceEpoch ?? missing;
    final order = {
      for (var i = 0; i < cards.length; i++) cards[i].sectionId: i,
    };
    cards.sort((a, b) {
      final byStamp = latest
          ? stamp(b).compareTo(stamp(a))
          : stamp(a).compareTo(stamp(b));
      if (byStamp != 0) return byStamp;
      return order[a.sectionId]!.compareTo(order[b.sectionId]!);
    });
  }

  Set<int> _conflictIds() {
    final picked = PlannerController.instance.pickedSections;
    if (picked.isEmpty || _cards.isEmpty) return const <int>{};
    final key = (
      Object.hashAll(_cards.map((card) => card.sectionId)),
      Object.hashAll(picked.map((section) => section.sectionId)),
    );
    if (key == _conflictKey) return _conflictCache;
    final plannedBlocks = [
      for (final section in picked)
        (planCourseKey(section.courseCode), sectionBlocks(section)),
    ];
    final conflicts = <int>{};
    for (final card in _cards) {
      final course = planCourseKey(card.courseCode);
      final blocks = routineBlocks([
        ...card.classSchedule,
        ...card.labSchedule,
      ]);
      for (final (plannedCourse, planned) in plannedBlocks) {
        if (plannedCourse != course && blocksClash(blocks, planned)) {
          conflicts.add(card.sectionId);
          break;
        }
      }
    }
    _conflictKey = key;
    _conflictCache = conflicts;
    return conflicts;
  }

  List<Widget> _plannedSeatCards() {
    final picked = PlannerController.instance.pickedSections;
    if (picked.isEmpty) return const <Widget>[];
    final cardsById = {for (final card in _cards) card.sectionId: card};
    return [
      for (final section in picked)
        _seatCard(
          cardsById[section.sectionId] ?? SeatCardData.fromDetails(section),
        ),
    ];
  }

  Widget _seatCard(SeatCardData item) {
    final current = _selectedArchive.isEmpty;
    final planned =
        current &&
        PlannerController.instance.isPlanned(item.courseCode, item.sectionId);
    final conflict = current && _conflictIds().contains(item.sectionId);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SeatCard(
        item: item,
        highlighted: planned || conflict,
        highlightColor: conflict ? AppPalette.warning : AppPalette.accent,
        onPinTap: current ? () => _togglePin(item) : null,
        pinned: _isPinnedSection(item.sectionId),
        planned: planned,
        onPlanTap: current ? () => _togglePlan(item) : null,
        onTap: () => _showFacultyScheduleSheet(
          item.facultyInitial,
          item.faculty?.staffName,
        ),
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
          const Gap(12),
          _buildFilterActions(context),
        ],
      ),
    );
  }

  Widget _buildSearchField(BuildContext context) {
    return AppSearchField(
      controller: _searchController,
      query: _searchQuery,
      keySuffix: 'seat',
    );
  }

  Widget _buildFilterActions(BuildContext context) {
    return SeatFilterBar(
      availableOnly: _availableOnly,
      mode: _selectedModeFilter,
      day: _selectedDayFilter,
      time: _selectedTimeFilter,
      times: sortedSeatFilterTimes(_cards.expand((card) => card.timetables)),
      onAvailableChanged: _setAvailableFilter,
      onModeChanged: _setModeFilter,
      onDayChanged: _setDayFilter,
      onTimeChanged: _setTimeFilter,
      hideConflicts: _selectedArchive.isEmpty ? _hideConflicts : null,
      onHideConflictsChanged: (next) =>
          _updateSeatStatusState(() => _hideConflicts = next),
      updateSort: _selectedArchive.isEmpty ? _updateSort : null,
      onUpdateSortChanged: (next) =>
          _updateSeatStatusState(() => _updateSort = next),
      onReset: _canResetFilters ? _resetFilters : null,
    );
  }

  bool get _canResetFilters =>
      _searchQuery.isNotEmpty ||
      _availableOnly ||
      _hideConflicts ||
      _updateSort.isNotEmpty ||
      _selectedDayFilter.isNotEmpty ||
      _selectedModeFilter.isNotEmpty ||
      _selectedTimeFilter.isNotEmpty;

  void _resetFilters() {
    _searchController.clear();
    _updateSeatStatusState(() {
      _hideConflicts = false;
      _updateSort = '';
    });
    _refreshVisibleCards(
      availableOnly: false,
      dayFilter: '',
      modeFilter: '',
      timeFilter: const SeatTimetable(startTime: '', endTime: ''),
      query: '',
    );
  }

  void _setAvailableFilter(bool next) {
    if (next == _availableOnly) return;
    _refreshVisibleCards(availableOnly: next);
  }

  void _setModeFilter(String next) {
    if (next == _selectedModeFilter.toString()) return;
    _refreshVisibleCards(modeFilter: next);
  }

  void _setDayFilter(String next) {
    if (next == _selectedDayFilter) return;
    _refreshVisibleCards(dayFilter: next);
  }

  void _setTimeFilter(SeatTimetable next) {
    if (next == _selectedTimeFilter) return;
    _refreshVisibleCards(timeFilter: next);
  }

  void _refreshVisibleCards({
    bool? availableOnly,
    bool? labOnly,
    String? dayFilter,
    String? modeFilter,
    SeatTimetable? timeFilter,
    String? query,
  }) {
    final resolvedAvailableOnly = availableOnly ?? _availableOnly;
    final resolvedLabOnly = labOnly ?? _labOnly;
    final resolvedDayFilter = dayFilter ?? _selectedDayFilter;
    final resolvedModeFilter = modeFilter ?? _selectedModeFilter;
    final resolvedTimeFilter = timeFilter ?? _selectedTimeFilter;
    final resolvedQuery = query ?? _searchQuery;
    final nextVisible = _filterCards(
      _cards,
      resolvedQuery,
      availableOnly: resolvedAvailableOnly,
      dayFilter: resolvedDayFilter,
      modeFilter: resolvedModeFilter,
      timeFilter: resolvedTimeFilter,
    );
    final filtersChanged =
        resolvedAvailableOnly != _availableOnly ||
        resolvedLabOnly != _labOnly ||
        resolvedDayFilter != _selectedDayFilter ||
        resolvedModeFilter != _selectedModeFilter ||
        resolvedTimeFilter != _selectedTimeFilter ||
        resolvedQuery != _searchQuery;
    if (!filtersChanged &&
        !_areCardListsDifferent(_visibleCards, nextVisible)) {
      return;
    }
    _updateSeatStatusState(() {
      _availableOnly = resolvedAvailableOnly;
      _labOnly = resolvedLabOnly;
      _selectedDayFilter = resolvedDayFilter;
      _selectedTimeFilter = resolvedTimeFilter;
      _selectedModeFilter = resolvedModeFilter;
      _searchQuery = resolvedQuery;
      _visibleCards
        ..clear()
        ..addAll(nextVisible);
    });
    _refreshIfActive();
  }

  List<SeatCardData> _filterCards(
    List<SeatCardData> source,
    String query, {
    required bool availableOnly,
    required String dayFilter,
    required SeatTimetable timeFilter,
    required String modeFilter,
  }) {
    final q = query.trim().toLowerCase();
    return source.where((card) {
      if (q.isNotEmpty && !card.searchToken.contains(q)) return false;
      return matchesSeatFilters(
        availableOnly: availableOnly,
        remaining: card.remaining,
        mode: modeFilter,
        hasLabSection: card.labSectionId != null,
        theorySchedules: card.classSchedule,
        labSchedules: card.labSchedule,
        day: dayFilter,
        time: timeFilter,
      );
    }).toList();
  }

  void _updateSearchQuery(String nextQuery) {
    if (nextQuery == _searchQuery) return;
    _refreshVisibleCards(query: nextQuery);
  }

  void _applyCardsSnapshot(
    List<SeatCardData> nextCards, {
    bool? isInitialLoading,
  }) {
    final nextVisible = _filterCards(
      nextCards,
      _searchQuery,
      availableOnly: _availableOnly,
      dayFilter: _selectedDayFilter,
      modeFilter: _selectedModeFilter,
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
    _updateSeatStatusState(() {
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
    _refreshIfActive();
  }

  void _sortCardsByCourseAndSection(List<SeatCardData> cards) {
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

  bool _areCardListsDifferent(List<SeatCardData> a, List<SeatCardData> b) {
    if (identical(a, b)) return false;
    if (a.length != b.length) return true;
    for (var i = 0; i < a.length; i++) {
      if (!_isSameCard(a[i], b[i])) return true;
    }
    return false;
  }

  bool _isSameCard(SeatCardData x, SeatCardData y) {
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
    if (x.lastUpdatedAt != y.lastUpdatedAt) return false;
    if (x.seatTrend != y.seatTrend) return false;
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

  void _refreshIfActive() {
    _syncSeatStream();
    final shouldRefresh =
        mounted &&
        _selectedArchive.isEmpty &&
        HomeTabRegistry.activeTab.value == HomeTab.seatStatus &&
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.paused &&
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.detached;
    if (shouldRefresh) {
      unawaited(_refreshDetailsFromApi());
    }
  }

  Future<void> _refreshFromButton() async {
    final refresh = _refreshDetailsFromApi(forceRefresh: true);
    _updateSeatStatusState(() {});
    await refresh;
  }

  Future<void> _refreshDetailsFromApi({bool forceRefresh = false}) async {
    if (_isDetailsRefreshing) return;
    final generation = _requestGeneration;
    final archive = _selectedArchive;
    _isDetailsRefreshing = true;
    try {
      final details = archive.isEmpty
          ? await _service.fetchRealtimeSections(forceRefresh: forceRefresh)
          : await _service.fetchArchiveSections(archive);
      if (!mounted || generation != _requestGeneration) return;
      _applyDetailsUpdate(details);
    } catch (error) {
      if (!mounted || generation != _requestGeneration) return;
      unawaited(AppLog.write('Seat status load failed: $error'));
    } finally {
      if (mounted && generation == _requestGeneration) {
        _updateSeatStatusState(() {
          _isDetailsRefreshing = false;
          _isInitialLoading = false;
        });
      }
    }
  }

  bool _isPinnedSection(int sectionId) {
    return _selectedArchive.isEmpty && SeatPins.instance.contains(sectionId);
  }

  void _showFacultyScheduleSheet(String facultyInitial, String? staffName) {
    if (facultyInitial.trim().isEmpty) return;

    final items = <FacultyScheduleItem>[];
    for (final card in _cards) {
      if (card.facultyInitial.trim().toUpperCase() ==
          facultyInitial.trim().toUpperCase()) {
        for (final sc in card.classSchedule) {
          items.add(
            FacultyScheduleItem(
              courseCode: card.courseCode,
              sectionName: card.sectionName,
              day: sc.day,
              startTime: sc.startTime,
              endTime: sc.endTime,
              roomNumber: card.room,
              consumedSeat: card.consumed,
              courseType: card.courseType,
            ),
          );
        }
        for (final sc in card.labSchedule) {
          items.add(
            FacultyScheduleItem(
              courseCode: card.courseCode,
              sectionName: card.sectionName,
              day: sc.day,
              startTime: sc.startTime,
              endTime: sc.endTime,
              roomNumber: card.labRoom.isNotEmpty ? card.labRoom : card.room,
              consumedSeat: card.consumed,
              courseType: 'Lab',
            ),
          );
        }
      }
    }

    showFacultyScheduleSheet(
      context,
      facultyInitial: facultyInitial,
      staffName: staffName,
      items: items,
      isRamadan: _selectedArchive.isEmpty && _isRamadan,
    );
  }
}
