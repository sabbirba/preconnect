// ignore_for_file: invalid_use_of_protected_member

part of 'package:preconnect/pages/seat_status.dart';

extension _SeatStatusPageStateMethods on _SeatStatusPageState {
  Widget _buildSeatAlertRuleCard(
    BuildContext context, {
    required String label,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final textPrimary = BracuPalette.textPrimary(context);
    final textSecondary = BracuPalette.textSecondary(context);
    return BracuCard(
      isHighlighted: value,
      highlightColor: BracuPalette.primary,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Switch.adaptive(value: value, onChanged: onChanged),
        ],
      ),
    );
  }

  _SeatStatusCardData _buildFallbackCard({
    required int sectionId,
    required int remaining,
  }) {
    return _SeatStatusCardData(
      sectionId: sectionId,
      courseCode: 'SEC$sectionId',
      sectionName: '--',
      courseName: 'Loading...',
      facultyInitial: 'TBA',
      facultyName: '',
      facultyEmail: '',
      facultyMeta: '',
      credits: 0,
      room: '',
      classSchedule: const <SeatStatusClassSchedule>[],
      labSchedule: const <SeatStatusClassSchedule>[],
      labRoom: '',
      midExamDate: null,
      midExamStartTime: null,
      midExamEndTime: null,
      finalExamDate: null,
      finalExamStartTime: null,
      finalExamEndTime: null,
      remaining: remaining,
      consumed: 0,
      total: 0,
      searchToken: 'sec$sectionId loading tba $remaining',
    );
  }

  Set<int> _visibleSectionIdsFromDetails(
    Map<int, SeatStatusDetailsResponse> detailsMap,
  ) {
    final childIds = <int>{};
    for (final details in detailsMap.values) {
      final childId = details.childSection?.sectionId ?? 0;
      if (childId > 0) childIds.add(childId);
    }
    return detailsMap.keys.where((id) => !childIds.contains(id)).toSet();
  }

  _SeatStatusCardData _buildCardFromDetails({
    required int sectionId,
    required SeatStatusDetailsResponse details,
  }) {
    final main = details.section;
    final lab = details.childSection;
    final total = main.capacity;
    final resolvedRemaining = total - main.consumedSeat;
    final resolvedConsumed = main.consumedSeat;
    return _SeatStatusCardData(
      sectionId: sectionId,
      courseCode: _pickNonEmpty(main.courseCode, 'SEC$sectionId'),
      sectionName: _pickNonEmpty(main.sectionName, '--'),
      courseName: _pickNonEmpty(main.name, 'Section $sectionId'),
      facultyInitial: _pickNonEmpty(main.faculties, 'TBA'),
      facultyName: _facultyNameForInitial(main.faculties),
      facultyEmail: _facultyEmailForInitial(main.faculties),
      facultyMeta: _facultyMetaForInitial(main.faculties),
      credits: main.courseCredit,
      room: _pickNonEmpty(main.roomNumber, ''),
      classSchedule: main.sectionSchedule.classSchedules,
      labSchedule:
          lab?.sectionSchedule.classSchedules ??
          const <SeatStatusClassSchedule>[],
      labRoom: _pickNonEmpty(lab?.roomNumber, ''),
      midExamDate: main.sectionSchedule.midExamDate,
      midExamStartTime: main.sectionSchedule.midExamStartTime,
      midExamEndTime: main.sectionSchedule.midExamEndTime,
      finalExamDate: main.sectionSchedule.finalExamDate,
      finalExamStartTime: main.sectionSchedule.finalExamStartTime,
      finalExamEndTime: main.sectionSchedule.finalExamEndTime,
      remaining: resolvedRemaining,
      consumed: resolvedConsumed,
      total: total,
      searchToken: _buildSearchToken(
        sectionId: sectionId,
        courseCode: _pickNonEmpty(main.courseCode, 'SEC$sectionId'),
        sectionName: _pickNonEmpty(main.sectionName, '--'),
        courseName: _pickNonEmpty(main.name, 'Section $sectionId'),
        facultyInitial: _pickNonEmpty(main.faculties, 'TBA'),
        facultyName: _facultyNameForInitial(main.faculties),
        facultyEmail: _facultyEmailForInitial(main.faculties),
        facultyMeta: _facultyMetaForInitial(main.faculties),
        room: _pickNonEmpty(main.roomNumber, ''),
        labRoom: _pickNonEmpty(lab?.roomNumber, ''),
        classSchedule: main.sectionSchedule.classSchedules,
        labSchedule:
            lab?.sectionSchedule.classSchedules ??
            const <SeatStatusClassSchedule>[],
        midExamDate: main.sectionSchedule.midExamDate,
        midExamStartTime: main.sectionSchedule.midExamStartTime,
        midExamEndTime: main.sectionSchedule.midExamEndTime,
        finalExamDate: main.sectionSchedule.finalExamDate,
        finalExamStartTime: main.sectionSchedule.finalExamStartTime,
        finalExamEndTime: main.sectionSchedule.finalExamEndTime,
        total: total,
        consumed: resolvedConsumed,
        remaining: resolvedRemaining,
      ),
    );
  }

  String _buildSearchToken({
    required int sectionId,
    required String courseCode,
    required String sectionName,
    required String courseName,
    required String facultyInitial,
    required String facultyName,
    required String facultyEmail,
    required String facultyMeta,
    required String room,
    required String labRoom,
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
            '$facultyInitial $facultyName $facultyEmail $facultyMeta '
            '$room $labRoom $sectionId $total $consumed $remaining '
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
    final showLoadingState =
        _isInitialLoading || (_cards.isEmpty && _isDetailsRefreshing);
    final hasCards = _cards.isNotEmpty;
    final hasVisibleCards = _visibleCards.isNotEmpty;
    final itemCount = hasVisibleCards ? _visibleCards.length + 1 : 2;

    return BracuPageScaffold(
      title: 'Seat Status',
      subtitle: 'Live Sections',
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
          BracuRefreshListBuilder(
            onRefresh: _handleRefresh,
            itemCount: itemCount,
            itemBuilder: (context, index) {
              if (index == 0) {
                return _buildFilterHeader(context);
              }
              if (showLoadingState) {
                return const Padding(
                  padding: EdgeInsets.only(top: 28),
                  child: _SeatStatusLoadingState(),
                );
              }
              if (!hasCards) {
                return const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: BracuEmptyState(message: 'No section data available'),
                );
              }
              if (!hasVisibleCards) {
                return const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: BracuEmptyState(message: 'No matching section found'),
                );
              }
              final item = _visibleCards[index - 1];
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _SeatStatusCard(
                  item: item,
                  hasAlert: _seatAlerts[item.sectionId]?.hasAnyRule == true,
                  onAlertTap: () => _handleSeatAlertTap(item),
                  onTap: () => _openCourseCommunitySheet(item),
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
        crossAxisAlignment: CrossAxisAlignment.start,
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
          _buildAlertsFilterAction(),
          _buildDayFilterAction(context),
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

  Widget _buildAlertsFilterAction() {
    return _FilterChip(
      icon: Icons.notifications_active_outlined,
      label: 'Alerts',
      selected: _alertsOnly,
      onTap: () => _setAlertsFilter(!_alertsOnly),
      showArrow: false,
    );
  }

  void _setAvailableFilter(bool next) {
    if (next == _availableOnly) return;
    _refreshVisibleCards(availableOnly: next);
  }

  void _setAlertsFilter(bool next) {
    if (next == _alertsOnly) return;
    _refreshVisibleCards(alertsOnly: next);
  }

  void _setDayFilter(String next) {
    if (next == _selectedDayFilter) return;
    _refreshVisibleCards(dayFilter: next);
  }

  void _refreshVisibleCards({
    bool? availableOnly,
    bool? alertsOnly,
    String? dayFilter,
    String? query,
  }) {
    final resolvedAvailableOnly = availableOnly ?? _availableOnly;
    final resolvedAlertsOnly = alertsOnly ?? _alertsOnly;
    final resolvedDayFilter = dayFilter ?? _selectedDayFilter;
    final resolvedQuery = query ?? _searchQuery;
    final nextVisible = _filterCards(
      _cards,
      resolvedQuery,
      availableOnly: resolvedAvailableOnly,
      alertsOnly: resolvedAlertsOnly,
      dayFilter: resolvedDayFilter,
    );
    final filtersChanged =
        resolvedAvailableOnly != _availableOnly ||
        resolvedAlertsOnly != _alertsOnly ||
        resolvedDayFilter != _selectedDayFilter ||
        resolvedQuery != _searchQuery;
    if (!filtersChanged &&
        !_areCardListsDifferent(_visibleCards, nextVisible)) {
      return;
    }
    setState(() {
      _availableOnly = resolvedAvailableOnly;
      _alertsOnly = resolvedAlertsOnly;
      _selectedDayFilter = resolvedDayFilter;
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
    required bool alertsOnly,
    required String dayFilter,
  }) {
    final q = query.trim().toLowerCase();
    return source.where((card) {
      if (q.isNotEmpty && !card.searchToken.contains(q)) return false;
      if (availableOnly && card.remaining <= 0) return false;
      if (alertsOnly && _seatAlerts[card.sectionId]?.hasAnyRule != true) {
        return false;
      }

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
      alertsOnly: _alertsOnly,
      dayFilter: _selectedDayFilter,
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
      final codeCmp = a.courseCode.compareTo(b.courseCode);
      if (codeCmp != 0) return codeCmp;
      final sectionCmp = _sectionOrder(
        a.sectionName,
      ).compareTo(_sectionOrder(b.sectionName));
      if (sectionCmp != 0) return sectionCmp;
      return a.sectionName.compareTo(b.sectionName);
    });
  }

  int _compareSectionIdsByNaming(int a, int b) {
    final aDetails = _detailsCache[a]?.section;
    final bDetails = _detailsCache[b]?.section;
    final aCode = _pickNonEmpty(aDetails?.courseCode, 'SEC$a');
    final bCode = _pickNonEmpty(bDetails?.courseCode, 'SEC$b');
    final codeCmp = aCode.compareTo(bCode);
    if (codeCmp != 0) return codeCmp;
    final aSection = _pickNonEmpty(aDetails?.sectionName, '$a');
    final bSection = _pickNonEmpty(bDetails?.sectionName, '$b');
    final sectionCmp = _sectionOrder(
      aSection,
    ).compareTo(_sectionOrder(bSection));
    if (sectionCmp != 0) return sectionCmp;
    return aSection.compareTo(bSection);
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
    if (x.facultyName != y.facultyName) return false;
    if (x.facultyEmail != y.facultyEmail) return false;
    if (x.facultyMeta != y.facultyMeta) return false;
    if (x.credits != y.credits) return false;
    if (x.room != y.room) return false;
    if (x.labRoom != y.labRoom) return false;
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

  void _updatePollingStrategy() {
    final shouldRun =
        _isAppForeground &&
        HomeTabRegistry.activeTab.value == HomeTab.seatStatus;
    if (!shouldRun) {
      _stopSeatStatusStream();
      return;
    }
    if (!_shouldUseLiveSeatStream()) {
      _stopSeatStatusStream();
    } else {
      _startSeatStatusStream();
    }
    if (_cards.isEmpty) {
      unawaited(_refreshDetailsFromApi());
    }
  }

  bool _shouldUseLiveSeatStream() {
    final source = _visibleCards.isNotEmpty ? _visibleCards : _cards;
    if (source.isEmpty) return false;

    final now = DateTime.now();
    final today = normalizeWeekday(DateFormat('EEEE').format(now));
    final nowMinutes = now.hour * 60 + now.minute;

    for (final card in source) {
      for (final entry in <SeatStatusClassSchedule>[
        ...card.classSchedule,
        ...card.labSchedule,
      ]) {
        if (normalizeWeekday(entry.day) != today) continue;

        final startMinutes = BracuTime.toMinutes(entry.startTime);
        if (startMinutes == null) continue;
        final endMinutes = BracuTime.toMinutes(entry.endTime);

        final startsWithinOneHour =
            startMinutes >= nowMinutes && startMinutes - nowMinutes <= 60;
        final isOngoing =
            endMinutes != null &&
            nowMinutes >= startMinutes &&
            nowMinutes <= endMinutes;

        if (startsWithinOneHour || isOngoing) {
          return true;
        }
      }
    }

    return false;
  }

  Future<void> _refreshDetailsFromApi() async {
    if (_isDetailsRefreshing) return;
    if (mounted && _cards.isEmpty) {
      setState(() {
        _isDetailsRefreshing = true;
      });
    } else {
      _isDetailsRefreshing = true;
    }
    try {
      final details = await _service.fetchAllSectionsDetailsFromApi();
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
      if (mounted && _cards.isEmpty) {
        setState(() {
          _isDetailsRefreshing = false;
        });
      } else {
        _isDetailsRefreshing = false;
      }
    }
  }

  void _startSeatStatusStream() {
    if (_streamSubscription != null || _isStreamConnecting) return;
    unawaited(_connectSeatStatusStream());
  }

  void _stopSeatStatusStream() {
    _streamReconnectTimer?.cancel();
    _streamReconnectTimer = null;
    _streamRefreshDebounce?.cancel();
    _streamRefreshDebounce = null;
    unawaited(_streamSubscription?.cancel());
    _streamSubscription = null;
    _streamClient?.close();
    _streamClient = null;
    _isStreamConnecting = false;
  }

  Future<void> _connectSeatStatusStream() async {
    if (!_isAppForeground ||
        HomeTabRegistry.activeTab.value != HomeTab.seatStatus) {
      return;
    }
    if (_streamSubscription != null || _isStreamConnecting) return;
    _isStreamConnecting = true;
    _streamClient?.close();
    _streamClient = http.Client();
    try {
      final request = http.Request(
        'GET',
        Uri.parse(_service.seatStatusStreamUrl),
      )..headers['Accept'] = 'text/event-stream';
      final response = await _streamClient!
          .send(request)
          .timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) {
        throw StateError('SSE returned ${response.statusCode}');
      }
      _streamSubscription = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            _onStreamLine,
            onError: (_) => _scheduleStreamReconnect(),
            onDone: _scheduleStreamReconnect,
            cancelOnError: true,
          );
    } catch (_) {
      _scheduleStreamReconnect();
    } finally {
      _isStreamConnecting = false;
    }
  }

  void _onStreamLine(String line) {
    if (!line.startsWith('data:')) return;
    if (!_isAppForeground ||
        HomeTabRegistry.activeTab.value != HomeTab.seatStatus) {
      return;
    }
    _streamRefreshDebounce?.cancel();
    _streamRefreshDebounce = Timer(const Duration(milliseconds: 450), () {
      if (!mounted) return;
      unawaited(_refreshDetailsFromApi());
    });
  }

  void _scheduleStreamReconnect() {
    unawaited(_streamSubscription?.cancel());
    _streamSubscription = null;
    _streamClient?.close();
    _streamClient = null;
    _streamReconnectTimer?.cancel();
    final shouldRun =
        _isAppForeground &&
        HomeTabRegistry.activeTab.value == HomeTab.seatStatus;
    if (!shouldRun) return;
    _streamReconnectTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      _startSeatStatusStream();
    });
  }

  void _queueStaffInfoResolve(
    Iterable<SeatStatusDetailsResponse> detailsValues,
  ) {
    for (final details in detailsValues) {
      final main = details.section.faculties.trim().toUpperCase();
      if (main.isNotEmpty) _pendingInitials.add(main);
      final child = (details.childSection?.faculties ?? '')
          .trim()
          .toUpperCase();
      if (child.isNotEmpty) _pendingInitials.add(child);
    }
    if (_pendingInitials.isEmpty) return;
    if (_isResolvingStaffInfo) return;
    unawaited(_resolvePendingStaffInfo());
  }

  Future<void> _resolvePendingStaffInfo() async {
    if (_isResolvingStaffInfo) return;
    if (_pendingInitials.isEmpty) return;
    _isResolvingStaffInfo = true;
    try {
      while (_pendingInitials.isNotEmpty) {
        final batch = _pendingInitials.take(20).toList();
        _pendingInitials.removeAll(batch);
        final changed = await _resolveStaffInfoForInitials(batch.toSet());
        if (changed && mounted && _detailsCache.isNotEmpty) {
          final refreshed = _buildCardsFromDetailsMap(_detailsCache);
          _sortCardsByCourseAndSection(refreshed);
          _applyCardsSnapshot(refreshed, isInitialLoading: false);
        }
      }
    } finally {
      _isResolvingStaffInfo = false;
    }
  }

  Future<bool> _resolveStaffInfoForInitials(Set<String> initials) async {
    if (initials.isEmpty) return false;
    final missing = initials
        .where((key) => !_staffInfoByInitial.containsKey(key))
        .toSet();
    if (missing.isEmpty) return false;
    final resolved = await _service.resolveStaffInfoByInitials(missing);
    if (resolved.isEmpty) return false;
    var changed = false;
    for (final entry in resolved.entries) {
      if (_staffInfoByInitial.containsKey(entry.key)) continue;
      _staffInfoByInitial[entry.key] = entry.value;
      changed = true;
    }
    return changed;
  }

  String _facultyNameForInitial(String facultyInitial) {
    final key = facultyInitial.trim().toUpperCase();
    return (_staffInfoByInitial[key]?.staffName ?? '').trim();
  }

  String _facultyEmailForInitial(String facultyInitial) {
    final key = facultyInitial.trim().toUpperCase();
    return (_staffInfoByInitial[key]?.email ?? '').trim();
  }

  String _facultyMetaForInitial(String facultyInitial) {
    return '';
  }
}

class _SeatStatusLoadingState extends StatelessWidget {
  const _SeatStatusLoadingState();

  @override
  Widget build(BuildContext context) {
    return BracuShimmer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var index = 0; index < 4; index++) ...[
            if (index != 0) const SizedBox(height: 12),
            BracuCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  BracuSkeletonBox(width: 128, height: 15, radius: 7),
                  SizedBox(height: 8),
                  BracuSkeletonBox(width: 176, height: 12, radius: 6),
                  SizedBox(height: 8),
                  BracuSkeletonBox(
                    width: double.infinity,
                    height: 10,
                    radius: 5,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
