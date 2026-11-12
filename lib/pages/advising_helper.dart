import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:gap/gap.dart';
import 'package:preconnect/api/api_client.dart';
import 'package:preconnect/api/advising_service.dart';
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/api/planner_state.dart';
import 'package:preconnect/api/profile.dart';
import 'package:preconnect/api/seat_pins.dart';
import 'package:preconnect/api/seat_status.dart';
import 'package:preconnect/model/advising_phase.dart';
import 'package:preconnect/pages/shared_widgets/planner_actions.dart';
import 'package:preconnect/pages/shared_widgets/seat_card.dart';
import 'package:preconnect/pages/shared_widgets/seat_filters.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/app_storage.dart';
import 'package:preconnect/tools/ramadan.dart';
import 'package:preconnect/tools/routine_clash.dart';

class AdvisingHelperPage extends StatefulWidget {
  const AdvisingHelperPage({
    super.key,
    this.initialPhase = AdvisingPhase.phaseOne,
  });

  final AdvisingPhase initialPhase;

  @override
  State<AdvisingHelperPage> createState() => _AdvisingHelperPageState();
}

class _AdvisingHelperPageState extends State<AdvisingHelperPage> {
  static const Duration _idlePollInterval = Duration(seconds: 20);
  static const EdgeInsets _cardSpacing = EdgeInsets.only(bottom: 12);

  final AdvisingHelperService _service = AdvisingHelperService();
  final AdvisingAutoEngine _engine = AdvisingAutoEngine();
  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = true;
  String? _errorMessage;
  String? _portfolioId;
  String? _publicKey;
  String? _enrolledError;
  bool _isConfirming = false;
  bool _isRamadan = false;

  late AdvisingPhase _phase;
  List<AdvisingSectionRecord> _enrolled = const [];
  Map<int, SeatStatusDetailsResponse> _seatDetails = const {};
  Map<int, SeatStatusDetailsResponse>? _cardsSource;
  List<SeatCardData> _cardsCache = const [];
  final PlannerConflictCache _conflicts = PlannerConflictCache();
  Timer? _enrolledRefreshTimer;
  bool _isRefreshingEnrolled = false;
  SeatFilters _filters = SeatFilters.cleared;
  int _loadGeneration = 0;
  DateTime _lastIdlePoll = DateTime.now();

  @override
  void initState() {
    super.initState();
    _phase = _engine.isRunning ? _engine.phase : widget.initialPhase;
    _engine.addListener(_onEngineChange);
    PlannerController.instance.addListener(_onPlannerChanged);
    SeatPins.instance.addListener(_onPinsChanged);
    _searchController.addListener(() {
      if (!mounted) return;
      final query = _searchController.text.trim();
      setState(() => _filters = _filters.copyWith(query: query));
    });
    RamadanTiming.isRamadan().then((value) {
      if (mounted) setState(() => _isRamadan = value);
    });
    loadPlannerAndPins(context);
    unawaited(_load());
    _enrolledRefreshTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => unawaited(_pollEnrolled()),
    );
  }

  @override
  void dispose() {
    _engine.removeListener(_onEngineChange);
    PlannerController.instance.removeListener(_onPlannerChanged);
    SeatPins.instance.removeListener(_onPinsChanged);
    _enrolledRefreshTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onEngineChange() {
    if (mounted) setState(() {});
  }

  void _onPlannerChanged() {
    if (!mounted) return;
    _syncQueue();
    setState(() {});
  }

  void _onPinsChanged() {
    if (mounted) setState(() {});
  }

  void _syncQueue() {
    if (_isLoading || _errorMessage != null) return;
    final enrolledIds = {for (final sec in _enrolled) sec.sectionId};
    final enrolledByCourse = {
      for (final sec in _enrolled) planCourseKey(sec.courseCode): sec,
    };
    _engine.syncTargets([
      for (final picked in PlannerController.instance.pickedSections)
        if (!enrolledIds.contains(picked.sectionId))
          _targetFor(
            _seatDetails[picked.sectionId] ?? picked,
            enrolledByCourse[planCourseKey(picked.courseCode)],
          ),
    ]);
  }

  TargetSectionItem _targetFor(
    SeatStatusDetailsResponse detail,
    AdvisingSectionRecord? enrolledSameCourse,
  ) {
    final replaced =
        enrolledSameCourse != null &&
            enrolledSameCourse.sectionId != detail.sectionId
        ? enrolledSameCourse
        : null;
    return TargetSectionItem(
      sectionId: detail.sectionId,
      courseId: detail.courseId,
      courseCode: detail.courseCode,
      courseName: detail.courseName,
      sectionName: detail.sectionName,
      capacity: detail.capacity,
      consumedSeat: detail.consumedSeat,
      courseCredit: detail.courseCredit,
      labSectionId: detail.labSectionId,
      labSectionName: detail.labName,
      replacement: replaced == null
          ? null
          : AdvisingReplacementSource(
              sectionId: replaced.sectionId,
              courseCode: replaced.courseCode,
              sectionName: replaced.sectionName,
            ),
    );
  }

  Future<void> _load() async {
    if (!mounted) return;
    final generation = ++_loadGeneration;
    final phase = _phase;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _enrolledError = null;
    });

    try {
      final portfolioId = await resolvePortfolioId(
        prefs: AppStorage.instance,
        refreshProfile: () => ProfileService().getProfile(fromFetch: true),
      );
      if (portfolioId == null) {
        throw Exception('Failed to resolve student portfolio profile.');
      }

      String? sessionId;
      try {
        sessionId = await _service.fetchActiveSessionId(
          portfolioId,
          phase: phase,
        );
      } catch (_) {}
      final publicKey =
          sessionId ?? DateTime.now().millisecondsSinceEpoch.toString();
      final seatsFuture = _service.fetchRealtimeSections(
        portfolioId: portfolioId,
        phase: phase,
        publicKey: publicKey,
      );

      List<AdvisingSectionRecord> enrolled = const [];
      String? enrolledError;
      try {
        enrolled = await _fetchAdvisedSections(
          portfolioId,
          phase: phase,
          publicKey: publicKey,
        );
      } catch (error) {
        enrolledError = advisingErrorMessage(error);
      }
      final seatDetails = await seatsFuture;

      if (!mounted || generation != _loadGeneration) return;
      _portfolioId = portfolioId;
      _publicKey = publicKey;
      _enrolledError = enrolledError;
      if (_engine.isRunning) _engine.onSectionAdded = _refreshEnrolled;

      setState(() {
        _enrolled = enrolled;
        _engine.enrolledSections = enrolled;
        _seatDetails = seatDetails;
        _isLoading = false;
      });
      _syncQueue();
    } catch (e) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  bool _isCurrentSession(
    String portfolioId,
    String publicKey,
    AdvisingPhase phase,
  ) {
    return mounted &&
        phase == _phase &&
        portfolioId == _portfolioId &&
        publicKey == _publicKey;
  }

  Future<void> _refreshEnrolled() async {
    final portfolioId = _portfolioId;
    final publicKey = _publicKey;
    final phase = _phase;
    if (portfolioId == null || publicKey == null) return;
    List<AdvisingSectionRecord> sections;
    try {
      sections = await _fetchAdvisedSections(
        portfolioId,
        phase: phase,
        publicKey: publicKey,
      );
    } catch (error) {
      if (_isCurrentSession(portfolioId, publicKey, phase)) {
        setState(() => _enrolledError = advisingErrorMessage(error));
      }
      rethrow;
    }
    if (!_isCurrentSession(portfolioId, publicKey, phase)) return;
    setState(() {
      _enrolled = sections;
      _engine.enrolledSections = sections;
      _enrolledError = null;
    });
    _syncQueue();
  }

  Future<void> _pollEnrolled() async {
    if (_isLoading || _isRefreshingEnrolled) return;
    final isRunning = _engine.isRunning;
    final now = DateTime.now();
    if (!isRunning && now.difference(_lastIdlePoll) < _idlePollInterval) {
      return;
    }
    _isRefreshingEnrolled = true;
    try {
      if (isRunning) {
        await _refreshEnrolled();
      } else {
        _lastIdlePoll = now;
        await Future.wait([_refreshEnrolled(), _refreshSeats()]);
      }
    } catch (_) {
    } finally {
      _isRefreshingEnrolled = false;
    }
  }

  Future<List<AdvisingSectionRecord>> _fetchAdvisedSections(
    String portfolioId, {
    required AdvisingPhase phase,
    required String publicKey,
  }) async {
    try {
      return await _service.fetchAdvisedSections(
        portfolioId,
        phase: phase,
        publicKey: publicKey,
      );
    } on ApiException catch (error) {
      if (isMissingAdvisingPhaseResponse(error)) {
        return const <AdvisingSectionRecord>[];
      }
      rethrow;
    }
  }

  Future<void> _refreshSeats() async {
    final portfolioId = _portfolioId;
    final publicKey = _publicKey;
    final phase = _phase;
    if (portfolioId == null || publicKey == null) return;
    final details = await _service.fetchRealtimeSections(
      portfolioId: portfolioId,
      phase: phase,
      publicKey: publicKey,
    );
    if (!_isCurrentSession(portfolioId, publicKey, phase)) return;
    setState(() => _seatDetails = details);
    _syncQueue();
  }

  SeatStatusDetailsResponse? _detailForSection(
    int sectionId, {
    String? courseCode,
    String? sectionName,
  }) {
    final byId = _seatDetails[sectionId];
    if (byId != null) return byId;
    for (final picked in PlannerController.instance.pickedSections) {
      if (picked.sectionId == sectionId) return picked;
    }
    if (courseCode == null || sectionName == null) return null;
    final normalizedCode = courseCode.trim().toUpperCase();
    final normalizedSec = sectionName.trim();
    for (final entry in _seatDetails.values) {
      if (entry.courseCode.trim().toUpperCase() == normalizedCode &&
          entry.sectionName.trim() == normalizedSec) {
        return entry;
      }
    }
    return null;
  }

  List<SeatCardData> get _cards {
    if (identical(_cardsSource, _seatDetails)) return _cardsCache;
    _cardsSource = _seatDetails;
    _cardsCache = seatCardsFromDetails(_seatDetails.values);
    return _cardsCache;
  }

  Set<int> _conflictIds() =>
      _conflicts.ids(_cards, PlannerController.instance.pickedSections);

  List<SeatCardData> _remainingCards() {
    return _filters.apply(
      _cards,
      excludedIds: {
        for (final section in PlannerController.instance.pickedSections)
          section.sectionId,
        for (final sec in _enrolled) sec.sectionId,
        for (final item in _engine.targetSections) item.sectionId,
      },
      conflictIds: _conflictIds(),
      pinnedFirst: SeatPins.instance.contains,
    );
  }

  void _resetFilters() {
    _searchController.clear();
    setState(() => _filters = SeatFilters.cleared);
  }

  Future<void> _confirmDrop(AdvisingSectionRecord sec) async {
    await showAppConfirmationWithActionDialog(
      context,
      icon: Icons.remove_circle_outline_rounded,
      title: 'Drop Section?',
      message:
          'Are you sure you want to drop ${sec.courseCode} Section ${sec.sectionName}?',
      confirmLabel: 'Drop',
      cancelLabel: 'Cancel',
      confirmColor: AppPalette.danger,
      onConfirm: () => _drop(sec),
    );
  }

  Future<void> _promptConfirmAdvising() async {
    if (_portfolioId == null || _publicKey == null || _enrolled.isEmpty) return;
    final totalCredits = _enrolled.fold<int>(
      0,
      (sum, e) => sum + e.courseCredit,
    );
    await showAppConfirmationWithActionDialog(
      context,
      icon: Icons.check_circle_outline_rounded,
      title: 'Confirm Advising?',
      message:
          'You are about to confirm and finalize your advising registration for ${_enrolled.length} enrolled section(s) ($totalCredits credits). Are you sure?',
      confirmLabel: 'Confirm Advising',
      cancelLabel: 'Cancel',
      confirmColor: AppPalette.accent,
      onConfirm: _performConfirmAdvising,
    );
  }

  Future<void> _performConfirmAdvising() async {
    final portfolioId = _portfolioId;
    final publicKey = _publicKey;
    if (portfolioId == null || publicKey == null) return;
    setState(() => _isConfirming = true);
    try {
      await _service.confirmAdvising(
        portfolioId: portfolioId,
        publicKey: publicKey,
        phase: _phase,
      );
      if (mounted) {
        showAppSnackBar(context, 'Advising confirmed successfully! 🎉');
      }
      await _refreshEnrolled();
    } catch (e) {
      if (mounted) {
        showAppSnackBar(
          context,
          'Failed to confirm advising: ${advisingErrorMessage(e)}',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isConfirming = false);
      }
    }
  }

  Future<void> _drop(AdvisingSectionRecord sec) async {
    final portfolioId = _portfolioId;
    final publicKey = _publicKey;
    if (portfolioId == null || publicKey == null || !mounted) return;
    setState(() => _isLoading = true);
    try {
      await _service.dropSection(
        portfolioId: portfolioId,
        sectionId: sec.sectionId,
        publicKey: publicKey,
        phase: _phase,
      );
      _engine.addLog('Dropped ${sec.courseCode} Sec ${sec.sectionName}');
      if (mounted) {
        showAppSnackBar(
          context,
          'Dropped ${sec.courseCode} Sec ${sec.sectionName}',
        );
      }
      await Future.wait([_refreshEnrolled(), _refreshSeats()]);
    } catch (e) {
      if (mounted) showAppSnackBar(context, e.toString());
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
        _syncQueue();
      }
    }
  }

  void _toggleEngine() {
    if (_engine.isRunning) {
      _engine.stop();
      if (mounted) setState(() {});
      return;
    }
    final portfolioId = _portfolioId;
    if (portfolioId == null) {
      showAppSnackBar(context, 'Student profile is loading. Try refreshing.');
      return;
    }
    _syncQueue();
    if (_engine.targetSections.isEmpty) {
      showAppSnackBar(context, 'Plan sections with ➕ to auto-add.');
      return;
    }
    final key = _publicKey ?? DateTime.now().millisecondsSinceEpoch.toString();
    _publicKey = key;
    _engine.start(
      portfolioId: portfolioId,
      publicKey: key,
      phase: _phase,
      onSectionAdded: _refreshEnrolled,
    );
    if (mounted) setState(() {});
  }

  void _selectPhase(AdvisingPhase phase) {
    if (_phase == phase) return;
    _engine.reset(keepQueue: false);
    setState(() {
      _phase = phase;
      _enrolled = const [];
      _engine.enrolledSections = const [];
      _portfolioId = null;
      _publicKey = null;
      _errorMessage = null;
      _enrolledError = null;
    });
    unawaited(_load());
  }

  void _showFacultySchedule(SeatCardData item) {
    showSeatFacultySchedule(
      context,
      cards: _cards,
      facultyInitial: item.facultyInitial,
      staffName: item.faculty?.staffName,
      isRamadan: _isRamadan,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const AppPageScaffold(
        title: 'Advising',
        subtitle: 'Helper',
        icon: Icons.bolt_rounded,
        body: Center(child: AppLoading()),
      );
    }

    if (_errorMessage != null) {
      return AppPageScaffold(
        title: 'Advising',
        subtitle: 'Helper',
        icon: Icons.bolt_rounded,
        body: AppErrorState(
          title: 'Load Error',
          message: _errorMessage!,
          onRetry: _load,
        ),
      );
    }

    return AppPageScaffold(
      title: 'Advising',
      subtitle: 'Helper',
      icon: Icons.bolt_rounded,
      actions: [
        AppOpenInBrowserButton(
          url: ApiConfig.connectAdvisingUrl(_phase.pathSegment),
        ),
        AppRefreshButton(onPressed: _load, isLoading: _isLoading),
      ],
      body: Column(
        children: [
          _buildPhaseChips(),
          _buildEngineActions(),
          Expanded(
            child: Stack(
              children: [
                _buildSectionList(),
                PlannerScheduleButton(
                  picked: PlannerController.instance.pickedSections,
                  clashingIds: _conflictIds(),
                  isRamadan: _isRamadan,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhaseChips() {
    final textSecondary = AppPalette.textSecondary(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final phase in AdvisingPhase.values)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(phase.label),
                  selected: _phase == phase,
                  onSelected: (selected) {
                    if (selected) _selectPhase(phase);
                  },
                  selectedColor: AppPalette.primary.withValues(alpha: 0.15),
                  labelStyle: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _phase == phase ? AppPalette.primary : textSecondary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEngineActions() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AppActionButton(
            key: const ValueKey('advising-auto-add-button'),
            onPressed: _toggleEngine,
            label: _engine.isRunning ? 'Stop' : 'Start',
          ),
          if (_enrolled.isNotEmpty) ...[
            const Gap(10),
            AppActionButton(
              key: const ValueKey('advising-confirm-button'),
              icon: Icons.check_circle_outline_rounded,
              label: 'Confirm Advising',
              isLoading: _isConfirming,
              foregroundColor: AppPalette.accent,
              onPressed: _isConfirming ? null : _promptConfirmAdvising,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionList() {
    final remaining = _remainingCards();
    final header = _buildHeader(remainingEmpty: remaining.isEmpty);
    return AppRefreshListBuilder(
      onRefresh: () async {
        await _refreshEnrolled();
        await _refreshSeats();
      },
      itemCount: remaining.length + 2,
      itemBuilder: (context, index) {
        if (index == 0) return header;
        if (index > remaining.length) return const SizedBox(height: 64);
        return _seatCard(remaining[index - 1]);
      },
    );
  }

  Widget _buildHeader({required bool remainingEmpty}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_engine.activityLogs.isNotEmpty)
          Padding(
            padding: _cardSpacing,
            child: AppActivityLog(logs: _engine.activityLogs),
          ),
        ..._enrolledCards(),
        ..._queuedCards(),
        Padding(
          padding: _cardSpacing,
          child: AppSearchField(
            controller: _searchController,
            query: _filters.query,
          ),
        ),
        Padding(
          padding: _cardSpacing,
          child: SeatFilterBar.bound(
            filters: _filters,
            cards: _cards,
            onChanged: (value) => setState(() => _filters = value),
            onReset: _resetFilters,
          ),
        ),
        if (remainingEmpty)
          Padding(
            padding: _cardSpacing,
            child: AppEmptyCard(
              message: _filters.query.isEmpty
                  ? 'No realtime sections available.'
                  : 'No sections match your search.',
            ),
          ),
      ],
    );
  }

  List<Widget> _enrolledCards() {
    if (_enrolled.isEmpty) {
      if (_enrolledError == null) return const <Widget>[];
      return const [
        Padding(
          padding: _cardSpacing,
          child: AppEmptyCard(message: 'Unable to load enrolled sections.'),
        ),
      ];
    }
    return [
      for (final sec in _enrolled)
        _enrolledCard(
          sec,
          _detailForSection(
            sec.sectionId,
            courseCode: sec.courseCode,
            sectionName: sec.sectionName,
          ),
        ),
    ];
  }

  Widget _enrolledCard(
    AdvisingSectionRecord sec,
    SeatStatusDetailsResponse? detail,
  ) {
    final footer = Row(
      children: [
        const Expanded(
          child: Text(
            'Enrolled',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppPalette.accent,
            ),
          ),
        ),
        AppActionButton(
          icon: Icons.remove_circle_outline_rounded,
          label: 'Drop',
          foregroundColor: AppPalette.danger,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          onPressed: () => _confirmDrop(sec),
        ),
      ],
    );
    if (detail == null) {
      return _plainSectionCard(sec.courseCode, sec.sectionName, footer);
    }
    return _seatCard(
      SeatCardData.fromDetails(detail),
      footer: [footer],
      enrolled: true,
    );
  }

  List<Widget> _queuedCards() {
    return [
      for (final item in _engine.targetSections)
        _queuedCard(
          item,
          _detailForSection(
            item.sectionId,
            courseCode: item.courseCode,
            sectionName: item.sectionName,
          ),
        ),
    ];
  }

  Widget _queuedCard(
    TargetSectionItem item,
    SeatStatusDetailsResponse? detail,
  ) {
    final footer = _queueStatusFooter(item);
    if (detail == null) {
      return _plainSectionCard(item.courseCode, item.sectionName, footer);
    }
    return _seatCard(SeatCardData.fromDetails(detail), footer: [footer]);
  }

  Widget _queueStatusFooter(TargetSectionItem item) {
    final textSecondary = AppPalette.textSecondary(context);
    final message = item.message?.trim() ?? '';
    final (label, color) = switch (item.status) {
      TargetSectionStatus.idle => ('Queued', textSecondary),
      TargetSectionStatus.watching => ('Watching', AppPalette.primary),
      TargetSectionStatus.adding => ('Adding', AppPalette.warning),
      TargetSectionStatus.added => ('Added', AppPalette.accent),
      TargetSectionStatus.failed => (
        message.isEmpty ? 'Failed' : message,
        AppPalette.danger,
      ),
      TargetSectionStatus.skippedZeroSeats => (
        message.isEmpty ? 'No Seats' : message,
        textSecondary,
      ),
    };
    final replacement = item.replacement;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        if (replacement != null) ...[
          const Gap(4),
          Text(
            'Replaces ${replacement.courseCode} Sec ${replacement.sectionName}',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppPalette.warning,
            ),
          ),
        ],
      ],
    );
  }

  Widget _plainSectionCard(
    String courseCode,
    String sectionName,
    Widget footer,
  ) {
    return Padding(
      padding: _cardSpacing,
      child: AppCard(
        isHighlighted: true,
        highlightColor: AppPalette.accent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$courseCode - $sectionName',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppPalette.textPrimary(context),
              ),
            ),
            const Gap(12),
            footer,
          ],
        ),
      ),
    );
  }

  Widget _seatCard(
    SeatCardData item, {
    List<Widget> footer = const <Widget>[],
    bool enrolled = false,
  }) {
    return PlannerSeatCard(
      item: item,
      conflictIds: _conflictIds(),
      footer: footer,
      enrolled: enrolled,
      onTap: () => _showFacultySchedule(item),
    );
  }
}
