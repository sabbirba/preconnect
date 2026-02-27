import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/api/seat_status_service.dart';
import 'package:preconnect/pages/home_tab.dart';
import 'package:preconnect/model/seat_status_info.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/refresh_bus.dart';
import 'package:preconnect/tools/refresh_guard.dart';
import 'package:preconnect/tools/time_utils.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class SeatStatusPage extends StatefulWidget {
  const SeatStatusPage({super.key});

  @override
  State<SeatStatusPage> createState() => _SeatStatusPageState();
}

class _SeatStatusPageState extends State<SeatStatusPage>
    with WidgetsBindingObserver {
  final SeatStatusService _service = SeatStatusService();
  final List<_SeatStatusCardData> _cards = <_SeatStatusCardData>[];
  final List<_SeatStatusCardData> _visibleCards = <_SeatStatusCardData>[];
  final Map<int, SeatStatusDetailsResponse> _detailsCache =
      <int, SeatStatusDetailsResponse>{};
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  Timer? _realtimeTimer;
  Timer? _wsReconnectTimer;
  WebSocketChannel? _seatMapChannel;
  StreamSubscription<dynamic>? _seatMapSubscription;
  bool _isInitialLoading = true;
  String _searchQuery = '';
  int _hydrateToken = 0;
  bool _cacheLoaded = false;
  bool _isAppForeground = true;
  int _wsReconnectAttempt = 0;

  static const Duration _activePollInterval = Duration(seconds: 5);
  static const Duration _idlePollInterval = Duration(hours: 1);

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
    unawaited(_reloadAll());
    WidgetsBinding.instance.addObserver(this);
    HomeTabRegistry.activeTab.addListener(_onActiveTabChanged);
    _updatePollingStrategy();
    RefreshBus.instance.addListener(_onRefreshSignal);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    HomeTabRegistry.activeTab.removeListener(_onActiveTabChanged);
    _searchDebounce?.cancel();
    _realtimeTimer?.cancel();
    _wsReconnectTimer?.cancel();
    _closeSeatMapSocket();
    _searchController.dispose();
    RefreshBus.instance.removeListener(_onRefreshSignal);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _isAppForeground = true;
      _updatePollingStrategy();
      unawaited(_refreshRealtime());
      return;
    }
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _isAppForeground = false;
      _updatePollingStrategy();
    }
  }

  void _onActiveTabChanged() {
    if (!mounted) return;
    _updatePollingStrategy();
  }

  void _onRefreshSignal() {
    if (!mounted) return;
    if (RefreshBus.instance.reason == 'seat_status') {
      return;
    }
    unawaited(_handleRefresh(notify: false));
  }

  Future<void> _handleRefresh({bool notify = true}) async {
    if (!await ensureOnline(context, notify: notify)) {
      return;
    }
    await _refreshRealtime(hydrateAll: true, hydrateInBackground: true);
    if (notify) {
      RefreshBus.instance.notify(reason: 'seat_status');
    }
  }

  Future<void> _reloadAll({bool forceRefreshDetails = false}) async {
    if (mounted) {
      setState(() {
        _isInitialLoading = true;
      });
    }
    final cachedSeatMap = await _service.loadCachedSeatMap(
      maxAge: const Duration(hours: 1),
    );
    if (!_cacheLoaded || forceRefreshDetails) {
      final cached = await _service.loadCachedDetails(
        maxAge: const Duration(hours: 1),
      );
      if (cached.isNotEmpty) {
        _detailsCache
          ..clear()
          ..addAll(cached);
      }
      _cacheLoaded = true;
    }

    // Instant paint from local cache.
    if (cachedSeatMap.isNotEmpty && mounted) {
      final cachedCards = _buildCardsFromSeatMap(cachedSeatMap);
      _applyCardsSnapshot(cachedCards, isInitialLoading: false);
    }

    Map<int, int> seatMap = const <int, int>{};
    try {
      seatMap = await _service.fetchSeatStatusMap();
    } catch (_) {}
    if (!mounted) return;

    if (seatMap.isEmpty) {
      if (cachedSeatMap.isNotEmpty) return;
      _applyCardsSnapshot(
        const <_SeatStatusCardData>[],
        isInitialLoading: false,
      );
      return;
    }

    unawaited(_service.saveSeatMapCacheIfChanged(seatMap));
    final nextCards = _buildCardsFromSeatMap(seatMap);
    if (_areCardListsDifferent(_cards, nextCards) || _isInitialLoading) {
      _applyCardsSnapshot(nextCards, isInitialLoading: false);
    } else if (_isInitialLoading) {
      setState(() {
        _isInitialLoading = false;
      });
    }

    final sectionIds = seatMap.keys.toList()
      ..sort((a, b) => _compareSectionIdsByNaming(a, b));

    final idsToFetch = forceRefreshDetails
        ? sectionIds
        : sectionIds.where((id) => !_detailsCache.containsKey(id)).toList();
    if (idsToFetch.isNotEmpty) {
      await _hydrateDetailsParallel(idsToFetch, seatMap: seatMap);
    }
  }

  List<_SeatStatusCardData> _buildCardsFromSeatMap(Map<int, int> seatMap) {
    final sectionIds = seatMap.keys.toList()
      ..sort((a, b) => _compareSectionIdsByNaming(a, b));
    return sectionIds.map((sectionId) {
      final cached = _detailsCache[sectionId];
      if (cached != null) {
        return _buildCardFromDetails(
          sectionId: sectionId,
          details: cached,
          remaining: seatMap[sectionId],
        );
      }
      return _SeatStatusCardData.placeholder(
        sectionId: sectionId,
        remaining: seatMap[sectionId] ?? 0,
      );
    }).toList();
  }

  Future<void> _refreshRealtime({
    bool hydrateAll = false,
    bool hydrateInBackground = true,
  }) async {
    Map<int, int> seatMap = const <int, int>{};
    try {
      seatMap = await _service.fetchSeatStatusMap();
    } catch (_) {}
    if (!mounted || seatMap.isEmpty) return;
    await _applySeatMapUpdate(
      seatMap,
      hydrateAll: hydrateAll,
      hydrateInBackground: hydrateInBackground,
    );
  }

  Future<void> _applySeatMapUpdate(
    Map<int, int> seatMap, {
    bool hydrateAll = false,
    bool hydrateInBackground = true,
  }) async {
    if (!mounted || seatMap.isEmpty) return;
    unawaited(_service.saveSeatMapCacheIfChanged(seatMap));

    final nextIds = seatMap.keys.toSet();
    final existingIds = _cards.map((c) => c.sectionId).toSet();

    final updated = _cards.where((c) => nextIds.contains(c.sectionId)).map((c) {
      final remaining = seatMap[c.sectionId] ?? c.remaining;
      final consumed = c.total > 0
          ? (c.total - remaining).clamp(0, c.total)
          : c.consumed;
      return c.copyWith(remaining: remaining, consumed: consumed);
    }).toList();

    final addedIds = nextIds.difference(existingIds).toList()
      ..sort((a, b) => _compareSectionIdsByNaming(a, b));
    for (final sectionId in addedIds) {
      final cached = _detailsCache[sectionId];
      if (cached != null) {
        updated.add(
          _buildCardFromDetails(
            sectionId: sectionId,
            details: cached,
            remaining: seatMap[sectionId],
          ),
        );
      } else {
        updated.add(
          _SeatStatusCardData.placeholder(
            sectionId: sectionId,
            remaining: seatMap[sectionId] ?? 0,
          ),
        );
      }
    }

    _sortCardsByCourseAndSection(updated);
    if (_areCardListsDifferent(_cards, updated)) {
      _applyCardsSnapshot(updated);
    }

    final toFetch = hydrateAll
        ? (seatMap.keys.toList()
            ..sort((a, b) => _compareSectionIdsByNaming(a, b)))
        : addedIds.where((id) => !_detailsCache.containsKey(id)).toList();
    if (toFetch.isNotEmpty) {
      if (hydrateInBackground) {
        unawaited(_hydrateDetailsParallel(toFetch, seatMap: seatMap));
      } else {
        await _hydrateDetailsParallel(toFetch, seatMap: seatMap);
      }
    }
  }

  Future<void> _hydrateDetailsParallel(
    List<int> sectionIds, {
    required Map<int, int> seatMap,
    int concurrency = 12,
  }) async {
    if (sectionIds.isEmpty) return;
    final token = ++_hydrateToken;
    var cursor = 0;
    var chunkSize = math.max(8, concurrency);
    while (cursor < sectionIds.length) {
      final end = math.min(cursor + chunkSize, sectionIds.length);
      final batch = sectionIds.sublist(cursor, end);
      final batchDetails = await Future.wait(
        batch.map((sectionId) async {
          try {
            final details = await _service.fetchSectionDetails(sectionId);
            if (details == null) return null;
            return MapEntry(sectionId, details);
          } catch (_) {
            return null;
          }
        }),
      );
      if (!mounted || token != _hydrateToken) return;

      var changed = false;
      var failedCount = 0;
      final nextCards = List<_SeatStatusCardData>.from(_cards);
      for (final detail in batchDetails) {
        if (detail == null) {
          failedCount++;
          continue;
        }
        _detailsCache[detail.key] = detail.value;
        final index = nextCards.indexWhere((c) => c.sectionId == detail.key);
        if (index == -1) continue;
        final next = _buildCardFromDetails(
          sectionId: detail.key,
          details: detail.value,
          remaining: seatMap[detail.key] ?? nextCards[index].remaining,
        );
        if (!_isSameCard(nextCards[index], next)) {
          nextCards[index] = next;
          changed = true;
        }
      }
      if (changed) {
        _sortCardsByCourseAndSection(nextCards);
        if (_areCardListsDifferent(_cards, nextCards)) {
          _applyCardsSnapshot(nextCards);
        }
      }
      if (failedCount >= (batch.length / 2).ceil() && chunkSize > 4) {
        chunkSize = math.max(4, chunkSize ~/ 2);
      } else if (failedCount == 0 && chunkSize < 16) {
        chunkSize = math.min(16, chunkSize + 2);
      }
      cursor = end;
    }
  }

  _SeatStatusCardData _buildCardFromDetails({
    required int sectionId,
    required SeatStatusDetailsResponse details,
    required int? remaining,
  }) {
    final main = details.section;
    final lab = details.childSection;
    final total = main.capacity;
    final resolvedRemaining = remaining ?? (total - main.consumedSeat);
    final resolvedConsumed = (total - resolvedRemaining).clamp(0, total);
    return _SeatStatusCardData(
      sectionId: sectionId,
      courseCode: _pickNonEmpty(main.courseCode, 'SEC$sectionId'),
      sectionName: _pickNonEmpty(main.sectionName, '--'),
      courseName: _pickNonEmpty(main.name, 'Section $sectionId'),
      credits: main.courseCredit,
      faculty: _pickNonEmpty(main.faculties, ''),
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
        faculty: _pickNonEmpty(main.faculties, ''),
        room: _pickNonEmpty(main.roomNumber, ''),
      ),
    );
  }

  String _buildSearchToken({
    required int sectionId,
    required String courseCode,
    required String sectionName,
    required String courseName,
    required String faculty,
    required String room,
  }) {
    return '$courseCode $sectionName $courseName $faculty $room $sectionId'
        .toLowerCase();
  }

  @override
  Widget build(BuildContext context) {
    return BracuPageScaffold(
      title: 'Seat Status',
      subtitle: 'Live Sections',
      icon: Icons.insights_outlined,
      body: _isInitialLoading
          ? BracuRefreshPlaceholder(
              onRefresh: _handleRefresh,
              child: const BracuLoading(label: 'Loading seats...'),
            )
          : _cards.isEmpty
          ? BracuRefreshPlaceholder(
              onRefresh: _handleRefresh,
              child: const BracuEmptyState(
                message: 'No section data available',
              ),
            )
          : BracuRefreshListBuilder(
              onRefresh: _handleRefresh,
              itemCount: _visibleCards.isEmpty ? 3 : _visibleCards.length + 2,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return TextField(
                    controller: _searchController,
                    style: TextStyle(color: BracuPalette.textPrimary(context)),
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: 'Search by couse, faculty, etc.',
                      hintStyle: TextStyle(
                        color: BracuPalette.textSecondary(context),
                      ),
                      prefixIcon: Icon(
                        Icons.search,
                        color: BracuPalette.textSecondary(context),
                      ),
                      suffixIcon: _searchQuery.trim().isEmpty
                          ? null
                          : IconButton(
                              onPressed: () => _searchController.clear(),
                              icon: Icon(
                                Icons.close,
                                color: BracuPalette.textSecondary(context),
                              ),
                            ),
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: BracuPalette.textSecondary(
                            context,
                          ).withValues(alpha: 0.24),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: BracuPalette.primary,
                        ),
                      ),
                    ),
                  );
                }
                if (index == 1) {
                  return const SizedBox(height: 12);
                }
                if (_visibleCards.isEmpty) {
                  return const BracuCard(
                    child: BracuEmptyState(
                      message: 'No matching section found',
                    ),
                  );
                }
                final item = _visibleCards[index - 2];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _SeatStatusCard(item: item),
                );
              },
            ),
    );
  }

  List<_SeatStatusCardData> _filterCards(
    List<_SeatStatusCardData> source,
    String query,
  ) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return source;
    return source.where((card) => card.searchToken.contains(q)).toList();
  }

  void _updateSearchQuery(String nextQuery) {
    if (nextQuery == _searchQuery) return;
    final nextVisible = _filterCards(_cards, nextQuery);
    setState(() {
      _searchQuery = nextQuery;
      _visibleCards
        ..clear()
        ..addAll(nextVisible);
    });
  }

  void _applyCardsSnapshot(
    List<_SeatStatusCardData> nextCards, {
    bool? isInitialLoading,
  }) {
    final nextVisible = _filterCards(nextCards, _searchQuery);
    if (!mounted) return;
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
    if (x.credits != y.credits) return false;
    if (x.faculty != y.faculty) return false;
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

  void _restartRealtimeTimer(Duration interval) {
    _realtimeTimer?.cancel();
    _realtimeTimer = Timer.periodic(interval, (_) {
      unawaited(_refreshRealtime());
    });
  }

  void _updatePollingStrategy() {
    final isSeatsTab = HomeTabRegistry.activeTab.value == HomeTab.seatStatus;
    final active = _isAppForeground && isSeatsTab;
    final wsUrl = ApiConfig.seatWorkerWsUrl;
    if (active && wsUrl != null) {
      _realtimeTimer?.cancel();
      _startSeatMapSocket(wsUrl);
      return;
    }
    _closeSeatMapSocket();
    final interval = active ? _activePollInterval : _idlePollInterval;
    _restartRealtimeTimer(interval);
  }

  void _startSeatMapSocket(String wsUrl) {
    if (_seatMapSubscription != null) return;
    try {
      final channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      _seatMapChannel = channel;
      _seatMapSubscription = channel.stream.listen(
        (payload) => unawaited(_onSeatMapSocketPayload(payload)),
        onDone: _scheduleSocketReconnect,
        onError: (_) => _scheduleSocketReconnect(),
      );
      _wsReconnectAttempt = 0;
      unawaited(_refreshRealtime(hydrateInBackground: true));
    } catch (_) {
      _scheduleSocketReconnect();
    }
  }

  void _closeSeatMapSocket() {
    _wsReconnectTimer?.cancel();
    _wsReconnectTimer = null;
    _seatMapSubscription?.cancel();
    _seatMapSubscription = null;
    _seatMapChannel?.sink.close();
    _seatMapChannel = null;
    _wsReconnectAttempt = 0;
  }

  void _scheduleSocketReconnect() {
    _seatMapSubscription?.cancel();
    _seatMapSubscription = null;
    _seatMapChannel?.sink.close();
    _seatMapChannel = null;

    final isSeatsTab = HomeTabRegistry.activeTab.value == HomeTab.seatStatus;
    if (!_isAppForeground || !isSeatsTab) return;
    final wsUrl = ApiConfig.seatWorkerWsUrl;
    if (wsUrl == null || wsUrl.isEmpty) return;

    _wsReconnectTimer?.cancel();
    final backoffSeconds = math.min(30, math.max(1, 1 << _wsReconnectAttempt));
    _wsReconnectAttempt = math.min(6, _wsReconnectAttempt + 1);
    _wsReconnectTimer = Timer(Duration(seconds: backoffSeconds), () {
      if (!mounted) return;
      _startSeatMapSocket(wsUrl);
    });
  }

  Future<void> _onSeatMapSocketPayload(dynamic payload) async {
    if (!mounted) return;
    final text = payload is String ? payload : '$payload';
    Map<String, dynamic> decoded;
    try {
      final raw = jsonDecode(text);
      if (raw is! Map<String, dynamic>) return;
      decoded = raw;
    } catch (_) {
      return;
    }

    if (decoded['type'] != 'seat_map') return;
    final rawMap = decoded['seatMap'];
    if (rawMap is! Map) return;
    final seatMap = <int, int>{};
    for (final entry in rawMap.entries) {
      final sectionId = int.tryParse('${entry.key}');
      final remaining = int.tryParse('${entry.value}');
      if (sectionId != null && remaining != null) {
        seatMap[sectionId] = remaining;
      }
    }
    if (seatMap.isEmpty) return;
    await _applySeatMapUpdate(seatMap, hydrateInBackground: true);
  }
}

class _SeatStatusCard extends StatelessWidget {
  const _SeatStatusCard({required this.item});

  final _SeatStatusCardData item;

  @override
  Widget build(BuildContext context) {
    final textPrimary = BracuPalette.textPrimary(context);
    final textSecondary = BracuPalette.textSecondary(context);

    return BracuCard(
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
                    Text(
                      '${item.courseCode} - ${item.sectionName}',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.courseName,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: textSecondary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    RichText(
                      text: TextSpan(
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: textSecondary,
                        ),
                        children: [
                          TextSpan(
                            text: item.faculty.isEmpty ? 'TBA' : item.faculty,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: textSecondary,
                            ),
                          ),
                          TextSpan(text: '  •  ${item.credits} credits'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Row(
                children: [
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () {
                        showAppSnackBar(context, 'Seat alerts coming soon.');
                      },
                      child: Container(
                        width: 38,
                        height: 38,
                        decoration: const BoxDecoration(
                          color: BracuPalette.primary,
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.notifications_none_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          _SeatScheduleBlock(
            title: 'Class',
            lines: _scheduleLines(item.classSchedule),
          ),
          const SizedBox(height: 10),
          RichText(
            text: TextSpan(
              style: TextStyle(color: textSecondary, fontSize: 11),
              children: [
                const TextSpan(text: 'Room: '),
                TextSpan(
                  text: item.room.isEmpty ? '--' : item.room,
                  style: TextStyle(
                    color: textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _SeatScheduleBlock(
            title: 'Lab',
            lines: _scheduleLines(
              item.labSchedule,
              fallback: const <String>['-'],
            ),
          ),
          const SizedBox(height: 10),
          RichText(
            text: TextSpan(
              style: TextStyle(color: textSecondary, fontSize: 11),
              children: [
                const TextSpan(text: 'Room: '),
                TextSpan(
                  text: item.labRoom.isEmpty ? '--' : item.labRoom,
                  style: TextStyle(
                    color: textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
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
                  label: 'Consumed',
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
  }

  List<String> _scheduleLines(
    List<SeatStatusClassSchedule> schedules, {
    List<String> fallback = const <String>['-'],
  }) {
    if (schedules.isEmpty) return fallback;
    final lines = schedules.map((entry) {
      final day = formatWeekdayTitle(entry.day);
      final time = formatTimeRange(entry.startTime, entry.endTime);
      return '$day $time';
    }).toList();
    return lines;
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
            fontWeight: FontWeight.w700,
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
        Text(
          dateValue,
          style: TextStyle(
            color: BracuPalette.textPrimary(context),
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 1),
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
    if (raw == null || raw.trim().isEmpty) return '--';
    final parsed = BracuTime.parseDate(raw);
    if (parsed == null) return raw;
    return DateFormat('MMM d, y').format(parsed);
  }

  String _formatExamTime(String? start, String? end) {
    final range = formatTimeRange(start, end);
    if (range.isEmpty) return '--';
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
    required this.credits,
    required this.faculty,
    required this.room,
    required this.classSchedule,
    required this.labSchedule,
    required this.labRoom,
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

  factory _SeatStatusCardData.placeholder({
    required int sectionId,
    required int remaining,
  }) {
    return _SeatStatusCardData(
      sectionId: sectionId,
      courseCode: 'SEC$sectionId',
      sectionName: '--',
      courseName: 'Section $sectionId',
      credits: 0,
      faculty: '',
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
      searchToken: 'sec$sectionId -- section $sectionId $sectionId',
    );
  }

  final int sectionId;
  final String courseCode;
  final String sectionName;
  final String courseName;
  final int credits;
  final String faculty;
  final String room;
  final List<SeatStatusClassSchedule> classSchedule;
  final List<SeatStatusClassSchedule> labSchedule;
  final String labRoom;
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
      credits: credits,
      faculty: faculty,
      room: room,
      classSchedule: classSchedule,
      labSchedule: labSchedule,
      labRoom: labRoom,
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

int _sectionOrder(String sectionName) {
  final number = RegExp(r'\d+').firstMatch(sectionName)?.group(0);
  if (number == null) return 9999;
  return int.tryParse(number) ?? 9999;
}

String _pickNonEmpty(String? primary, String fallback) {
  final value = (primary ?? '').trim();
  if (value.isNotEmpty) return value;
  return fallback.trim();
}
