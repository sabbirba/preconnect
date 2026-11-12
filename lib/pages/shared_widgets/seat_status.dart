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
          if (_selectedArchive.isEmpty)
            PlannerScheduleButton(
              picked: PlannerController.instance.pickedSections,
              clashingIds: _conflictIds(),
              isRamadan: _isRamadan,
            ),
        ],
      ),
    );
  }

  List<SeatCardData> _unplannedCards() {
    if (_selectedArchive.isNotEmpty) return _visibleCards;
    return _filters.apply(
      _visibleCards,
      excludedIds: {
        for (final section in PlannerController.instance.pickedSections)
          section.sectionId,
      },
      conflictIds: _conflictIds(),
    );
  }

  Set<int> _conflictIds() =>
      _conflicts.ids(_cards, PlannerController.instance.pickedSections);

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
    return PlannerSeatCard(
      item: item,
      conflictIds: _conflictIds(),
      active: _selectedArchive.isEmpty,
      onTap: () => _showFacultyScheduleSheet(
        item.facultyInitial,
        item.faculty?.staffName,
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
      query: _filters.query,
      keySuffix: 'seat',
    );
  }

  Widget _buildFilterActions(BuildContext context) {
    return SeatFilterBar.bound(
      filters: _filters,
      cards: _cards,
      onChanged: _setFilters,
      onReset: _resetFilters,
      plannerFilters: _selectedArchive.isEmpty,
    );
  }

  void _resetFilters() {
    _searchController.clear();
    _setFilters(SeatFilters.cleared);
  }

  void _setFilters(SeatFilters next) {
    if (next == _filters) return;
    final matchingChanged = !next.sameMatching(_filters);
    final nextVisible = matchingChanged
        ? _cards.where(next.matches).toList()
        : null;
    _updateSeatStatusState(() {
      _filters = next;
      if (nextVisible != null) {
        _visibleCards
          ..clear()
          ..addAll(nextVisible);
      }
    });
    if (matchingChanged) _refreshIfActive();
  }

  void _applyCardsSnapshot(
    List<SeatCardData> nextCards, {
    bool? isInitialLoading,
  }) {
    final nextVisible = nextCards.where(_filters.matches).toList();
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
    showSeatFacultySchedule(
      context,
      cards: _cards,
      facultyInitial: facultyInitial,
      staffName: staffName,
      isRamadan: _selectedArchive.isEmpty && _isRamadan,
    );
  }
}
