import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:gap/gap.dart';
import 'package:preconnect/api/seat_pins.dart';
import 'package:preconnect/api/planner_state.dart';
import 'package:preconnect/api/seat_status.dart';
import 'package:preconnect/api/seat_stream.dart';
import 'package:preconnect/pages/home_tab.dart';
import 'package:preconnect/model/seat_timetable.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/ramadan.dart';
import 'package:preconnect/tools/refresh_bus.dart';
import 'package:preconnect/pages/shared_widgets/faculty_sheet.dart';
import 'package:preconnect/pages/shared_widgets/seat_filters.dart';
import 'package:preconnect/pages/shared_widgets/routine_sheet.dart';
import 'package:preconnect/pages/shared_widgets/seat_card.dart';
import 'package:preconnect/tools/routine_clash.dart';
import 'package:preconnect/tools/app_log.dart';
export 'package:preconnect/pages/shared_widgets/seat_card.dart'
    show
        seatStatusFacultySummaryLabel,
        seatStatusFacultyDetailLabel,
        seatStatusFacultySearchText,
        seatStatusFacultyHasVisuals;

part 'shared_widgets/seat_status.dart';

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
  final SeatStatusService _service = SeatStatusService();
  final List<SeatCardData> _cards = <SeatCardData>[];
  final List<SeatCardData> _visibleCards = <SeatCardData>[];
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  StreamSubscription<List<SeatCount>>? _seatStream;

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
  bool _hideConflicts = false;
  String _updateSort = '';
  Object? _conflictKey;
  Set<int> _conflictCache = const <int>{};

  @override
  void initState() {
    super.initState();
    RamadanTiming.isRamadan().then((value) {
      if (!mounted) return;
      setState(() {
        _isRamadan = value;
      });
    });
    unawaited(_seedCachedCards());
    _searchController.addListener(() {
      _searchDebounce?.cancel();
      _searchDebounce = Timer(const Duration(milliseconds: 150), () {
        if (!mounted) return;
        final next = _searchController.text.trim().toLowerCase();
        _updateSearchQuery(next);
      });
    });
    unawaited(_loadArchiveSemesters());
    SeatPins.instance.addListener(_onPinsChanged);
    PlannerController.instance.addListener(_onPlannerChanged);
    unawaited(_loadPlanner());
    unawaited(_loadPins());
    unawaited(_refreshDetailsFromApi());
    WidgetsBinding.instance.addObserver(this);
    HomeTabRegistry.activeTab.addListener(_onActiveTabChanged);
    bindRefreshBus(_onRefreshSignal);
    _syncSeatStream();
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

  Future<void> _seedCachedCards() async {
    final cachedDetails = await _service.loadCachedDetails();
    if (!mounted ||
        cachedDetails == null ||
        _cards.isNotEmpty ||
        _selectedArchive.isNotEmpty) {
      return;
    }
    _applyCardsSnapshot(
      _buildCardsFromDetailsMap(cachedDetails),
      isInitialLoading: false,
    );
  }

  @override
  void dispose() {
    unbindRefreshBus(_onRefreshSignal);
    SeatPins.instance.removeListener(_onPinsChanged);
    PlannerController.instance.removeListener(_onPlannerChanged);
    unawaited(_seatStream?.cancel());
    WidgetsBinding.instance.removeObserver(this);
    HomeTabRegistry.activeTab.removeListener(_onActiveTabChanged);
    _searchDebounce?.cancel();

    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshIfActive();
    } else {
      _syncSeatStream();
    }
  }

  void _syncSeatStream() {
    final state = WidgetsBinding.instance.lifecycleState;
    final shouldRun =
        mounted &&
        _selectedArchive.isEmpty &&
        HomeTabRegistry.activeTab.value == HomeTab.seatStatus &&
        state != AppLifecycleState.paused &&
        state != AppLifecycleState.detached &&
        state != AppLifecycleState.hidden;
    if (shouldRun && _seatStream == null) {
      _seatStream = SeatStream.instance.updates.listen(_applySeatCounts);
    } else if (!shouldRun && _seatStream != null) {
      unawaited(_seatStream!.cancel());
      _seatStream = null;
    }
  }

  void _applySeatCounts(List<SeatCount> counts) {
    if (!mounted || counts.isEmpty) return;
    PlannerController.instance.applySeatCounts(counts);
    if (_selectedArchive.isNotEmpty) return;
    final byId = {for (final count in counts) count.sectionId: count};
    var changed = false;
    final updated = <SeatCardData>[
      for (final card in _cards)
        if (byId[card.sectionId] case final count?
            when count.consumed != card.consumed ||
                (count.capacity != null && count.capacity != card.total))
          () {
            changed = true;
            final total = count.capacity ?? card.total;
            return card.copyWith(
              consumed: count.consumed,
              total: total,
              remaining: total - count.consumed,
              lastUpdatedAt: DateTime.now(),
              seatTrend: count.consumed == card.consumed
                  ? card.seatTrend
                  : count.consumed > card.consumed
                  ? 'down'
                  : 'up',
            );
          }()
        else
          card,
    ];
    if (changed) _applyCardsSnapshot(updated, isInitialLoading: false);
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
    try {
      await SeatPins.instance.load();
    } catch (_) {
      if (!mounted) return;
      showAppSnackBar(context, 'Could not load seat alerts.');
    }
  }

  void _onPinsChanged() {
    if (!mounted || _cards.isEmpty) return;
    final refreshed = List<SeatCardData>.from(_cards);
    _sortCardsByCourseAndSection(refreshed);
    _applyCardsSnapshot(refreshed, isInitialLoading: false);
  }

  Future<void> _loadPlanner() async {
    try {
      await PlannerController.instance.load();
    } catch (_) {
      if (!mounted) return;
      showAppSnackBar(context, 'Could not load your planner.');
    }
  }

  void _onPlannerChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _togglePlan(SeatCardData card) async {
    final planner = PlannerController.instance;
    final planned = planner.isPlanned(card.courseCode, card.sectionId);
    final label = '${card.courseCode} Section ${card.sectionName}';
    try {
      if (planned) {
        await planner.removeFromWishlist(card.courseCode);
      } else {
        await planner.plan(card.courseCode, card.sectionId);
      }
    } catch (_) {
      if (!mounted) return;
      showAppSnackBar(context, 'Could not save. Try again.');
      return;
    }
    if (!mounted) return;
    showAppSnackBar(
      context,
      planned ? '$label removed from planner' : '$label added to planner',
    );
  }

  Future<void> _togglePin(SeatCardData card) async {
    final result = await SeatPins.instance.toggle(
      card.sectionId,
      courseCode: card.courseCode,
      sectionName: card.sectionName,
    );
    if (!mounted) return;
    showAppSnackBar(
      context,
      seatPinMessage(
        result,
        courseCode: card.courseCode,
        sectionName: card.sectionName,
      ),
    );
  }

  List<SeatCardData> _buildCardsFromDetailsMap(
    Map<int, SeatStatusDetailsResponse> detailsMap,
  ) {
    final cards = <SeatCardData>[];
    for (final entry in detailsMap.entries) {
      cards.add(SeatCardData.fromDetails(entry.value));
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
