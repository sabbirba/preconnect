import 'package:material_ui/material_ui.dart';
import 'package:gap/gap.dart';
import 'package:preconnect/api/advising_service.dart';
import 'package:preconnect/api/api_client.dart';
import 'package:preconnect/api/profile.dart';
import 'package:preconnect/api/progress.dart';
import 'package:preconnect/api/wishlist_engine.dart';
import 'package:preconnect/pages/shared_widgets/seat_card.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/app_storage.dart';
import 'package:preconnect/tools/time_utils.dart';

enum _WishlistWindow { open, closed, completed }

typedef _CourseRow = ({
  String code,
  String name,
  int credit,
  Map<String, dynamic>? course,
});

class WishlistPage extends StatefulWidget {
  const WishlistPage({super.key});

  @override
  State<WishlistPage> createState() => _WishlistPageState();
}

class _WishlistPageState extends State<WishlistPage> {
  final WishlistService _service = WishlistService();
  final WishlistAutoEngine _engine = WishlistAutoEngine.instance;
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _pendingCodes = <String>{};
  bool _isLoading = true;
  bool _isConfirmed = false;
  bool _isConfirming = false;
  String? _errorMessage;
  String? _portfolioId;
  String? _publicKey;
  DateTime? _opensAt;
  _WishlistWindow _window = _WishlistWindow.closed;
  WishlistCreditLimit? _creditLimit;
  List<Map<String, dynamic>> _wishlistCourses = [];
  List<_CourseRow> _courseRows = [];
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _engine.addListener(_handleEngineChanged);
    if (_engine.isRunning) _engine.onWishlistChanged = _handleWishlistChanged;
    _loadInitialData();
    _searchController.addListener(() {
      if (!mounted || _searchQuery == _searchController.text) return;
      setState(() => _searchQuery = _searchController.text);
    });
  }

  @override
  void dispose() {
    _engine.removeListener(_handleEngineChanged);
    if (_engine.onWishlistChanged == _handleWishlistChanged) {
      _engine.onWishlistChanged = null;
    }
    _searchController.dispose();
    super.dispose();
  }

  void _handleEngineChanged() {
    if (mounted) setState(() {});
  }

  void _handleWishlistChanged() {
    if (mounted) _loadInitialData(showLoading: false);
  }

  Future<void> _loadInitialData({bool showLoading = true}) async {
    if (!mounted) return;
    if (showLoading) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      await _engine.load();
      final portfolioId = await resolvePortfolioId(
        prefs: AppStorage.instance,
        refreshProfile: () => ProfileService().getProfile(fromFetch: true),
      );
      if (portfolioId == null) {
        throw Exception('Failed to resolve student portfolio profile.');
      }
      _portfolioId = portfolioId;
      _opensAt = await _readOpensAt();
      await _openWindow(portfolioId);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = advisingErrorMessage(e);
        _isLoading = false;
      });
    }
  }

  Future<DateTime?> _readOpensAt() async {
    final info = await AdvisingService().getAdvisingInfo();
    final phase = (info?['advisingPhase'] ?? '').toUpperCase();
    if (phase.isNotEmpty && !phase.contains('WISHLIST')) return null;
    return DateTime.tryParse(info?['advisingStartDate'] ?? '');
  }

  Future<void> _openWindow(String portfolioId) async {
    final publicKey = DateTime.now().millisecondsSinceEpoch.toString();
    _publicKey = publicKey;
    try {
      _creditLimit = await _service.openSession(portfolioId, publicKey);
      _window = _WishlistWindow.open;
    } on ApiException catch (e) {
      if (e.statusCode == 404) {
        _window = _WishlistWindow.closed;
        await _loadCatalog();
        return;
      }
      if (e.statusCode != 412) rethrow;
      _window = _WishlistWindow.completed;
    }
    await _refreshWishlistData();
  }

  Future<void> _loadCatalog() async {
    final progress = await ProgressService().getProgress();
    final passedCodes = {
      for (final course in progress?.completedCourses ?? const [])
        if (course.isPassed) normalizeWishlistCode(course.code),
    };
    final rowsByCode = <String, _CourseRow>{};
    for (final course in progress?.curriculumCourses ?? const []) {
      final code = normalizeWishlistCode(course.code);
      if (code.isEmpty || passedCodes.contains(code)) continue;
      rowsByCode.putIfAbsent(
        code,
        () => (
          code: code,
          name: course.title,
          credit: course.credit.round(),
          course: null,
        ),
      );
    }
    if (!mounted) return;
    setState(() {
      _wishlistCourses = [];
      _courseRows = rowsByCode.values.toList(growable: false);
      _isConfirmed = false;
      _isLoading = false;
      _errorMessage = null;
    });
  }

  Future<void> _refreshWishlistData() async {
    final portfolioId = _portfolioId;
    final publicKey = _publicKey;
    if (portfolioId == null || publicKey == null) return;

    try {
      final results = await Future.wait([
        _service.fetchWishlist(portfolioId, publicKey),
        _service.fetchOffered(portfolioId, publicKey),
      ]);
      final confirmed = await _service.fetchConfirmed(portfolioId, publicKey);
      final wishlist = results[0];
      final options = mergeWishlistCourseOptions(wishlist, results[1]);

      if (!mounted) return;
      setState(() {
        _wishlistCourses = wishlist;
        _courseRows = [
          for (final course in options)
            (
              code: wishlistCourseCode(course),
              name: '${course['name']}',
              credit: wishlistCourseCredit(course),
              course: course,
            ),
        ];
        _isConfirmed = confirmed;
        _isLoading = false;
        _errorMessage = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = advisingErrorMessage(e);
        _isLoading = false;
      });
    }
  }

  List<_CourseRow> get _visibleRows {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return _courseRows;
    return _courseRows
        .where(
          (row) =>
              row.code.toLowerCase().contains(query) ||
              row.name.toLowerCase().contains(query),
        )
        .toList(growable: false);
  }

  bool _isInWishlist(_CourseRow row) {
    final course = row.course;
    return course != null && wishlistContainsCourse(_wishlistCourses, course);
  }

  void _onCourseTap(_CourseRow row) {
    final course = row.course;
    if (course != null && _isInWishlist(row)) {
      _mutateNow(row, () => _removeCourse(course));
      return;
    }
    final canAddNow =
        course != null &&
        _window == _WishlistWindow.open &&
        !_engine.isRunning &&
        !_engine.isQueued(row.code);
    if (canAddNow) {
      _mutateNow(row, () => _addCourse(course));
      return;
    }
    _engine.toggle(row.code, row.name, row.credit);
  }

  Future<void> _addCourse(Map<String, dynamic> course) =>
      _service.addCourse(_portfolioId!, _publicKey!, course);

  Future<void> _removeCourse(Map<String, dynamic> course) =>
      _service.removeCourse(_portfolioId!, _publicKey!, course);

  Future<void> _mutateNow(
    _CourseRow row,
    Future<void> Function() action,
  ) async {
    if (_portfolioId == null || _publicKey == null) return;
    if (_pendingCodes.contains(row.code)) return;
    setState(() => _pendingCodes.add(row.code));
    try {
      await action();
      await _refreshWishlistData();
    } catch (e) {
      if (mounted) showAppSnackBar(context, advisingErrorMessage(e));
    } finally {
      if (mounted) setState(() => _pendingCodes.remove(row.code));
    }
  }

  void _toggleEngine() {
    final portfolioId = _portfolioId;
    if (_engine.isRunning) {
      _engine.stop();
      return;
    }
    if (portfolioId == null) return;
    _engine.start(
      portfolioId: portfolioId,
      opensAt: _opensAt,
      onWishlistChanged: _handleWishlistChanged,
    );
  }

  Future<void> _promptConfirmWishlist() async {
    final count = _wishlistCourses.length;
    final credits = wishlistCredits(_wishlistCourses);
    await showAppConfirmationWithActionDialog(
      context,
      icon: Icons.check_circle_outline_rounded,
      title: 'Confirm Wishlist?',
      message:
          'Submit ${wishlistCourseCount(count)} ($credits credits) to Connect.',
      confirmLabel: 'Confirm',
      confirmColor: AppPalette.accent,
      onConfirm: _confirmWishlist,
    );
  }

  Future<void> _confirmWishlist() async {
    final portfolioId = _portfolioId;
    final publicKey = _publicKey;
    if (portfolioId == null || publicKey == null) return;
    setState(() => _isConfirming = true);
    try {
      await _service.confirm(portfolioId, publicKey);
      if (mounted) showAppSnackBar(context, 'Wishlist confirmed');
      await _refreshWishlistData();
    } catch (e) {
      if (mounted) showAppSnackBar(context, advisingErrorMessage(e));
    } finally {
      if (mounted) setState(() => _isConfirming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textPrimary = AppPalette.textPrimary(context);
    final textSecondary = AppPalette.textSecondary(context);
    final errorMessage = _errorMessage;
    final showAutoRun =
        _engine.queue.isNotEmpty ||
        _engine.activityLogs.isNotEmpty ||
        _engine.isRunning;

    Widget body;
    if (_isLoading) {
      body = const Center(child: AppLoading());
    } else if (errorMessage != null) {
      body = AppErrorState(
        title: 'Wishlist Unavailable',
        message: errorMessage,
        onRetry: _loadInitialData,
      );
    } else {
      final rows = _visibleRows;
      body = AppRefreshList(
        onRefresh: () => _loadInitialData(showLoading: false),
        children: [
          _buildSummary(textPrimary, textSecondary),
          if (showAutoRun) ...[
            const Gap(12),
            _buildAutoRun(textPrimary, textSecondary),
          ],
          const Gap(12),
          AppSearchField(controller: _searchController, query: _searchQuery),
          const Gap(12),
          if (rows.isEmpty)
            AppEmptyCard(
              message: _searchQuery.trim().isEmpty
                  ? 'No courses to choose'
                  : 'No matching courses',
            )
          else
            for (final row in rows)
              _buildCourseRow(row, textPrimary, textSecondary),
        ],
      );
    }

    return AppPageScaffold(
      title: 'Advising',
      subtitle: 'Wishlist',
      icon: Icons.star_outline_rounded,
      actions: [
        AppRefreshButton(onPressed: _loadInitialData, isLoading: _isLoading),
      ],
      body: body,
    );
  }

  Widget _buildSummary(Color textPrimary, Color textSecondary) {
    final count = _wishlistCourses.length;
    final credits = wishlistCredits(_wishlistCourses);
    final limit = _creditLimit;
    final withinLimit = isWithinWishlistLimit(credits, limit);
    final isOpen = _window == _WishlistWindow.open;
    final canConfirm = count > 0 && withinLimit && !_isConfirming;
    final statusColor = _isConfirmed
        ? AppPalette.accent
        : withinLimit || !isOpen
        ? textSecondary
        : AppPalette.warning;

    return AppCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${wishlistCourseCount(count)} · $credits credits',
                  style: TextStyle(
                    color: textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Gap(3),
                Text(
                  _summaryStatus(limit, withinLimit),
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (isOpen && !_isConfirmed) ...[
            const Gap(12),
            AppActionButton(
              icon: Icons.check_circle_outline_rounded,
              label: 'Confirm',
              isLoading: _isConfirming,
              foregroundColor: AppPalette.accent,
              onPressed: canConfirm ? _promptConfirmWishlist : null,
            ),
          ],
        ],
      ),
    );
  }

  String _summaryStatus(WishlistCreditLimit? limit, bool withinLimit) {
    if (_window == _WishlistWindow.completed) return 'Wishlist phase completed';
    if (_window == _WishlistWindow.closed) {
      final opensAt = _opensAt;
      return opensAt == null
          ? 'Wishlist is not open yet'
          : 'Opens at ${AppTime.formatDateTime(opensAt)}';
    }
    if (_isConfirmed) return 'Confirmed on Connect';
    if (limit == null) return 'Not confirmed';
    final range = '${limit.min}–${limit.max} credits';
    return withinLimit ? 'Limit $range' : 'Choose $range to confirm';
  }

  String _autoRunStatus() {
    final queued = '${_engine.queue.length} queued';
    final opensAt = _opensAt;
    if (_window == _WishlistWindow.open) return '$queued · Wishlist open';
    if (opensAt == null) return queued;
    return '$queued · opens ${AppTime.formatDateTime(opensAt)}';
  }

  Widget _buildAutoRun(Color textPrimary, Color textSecondary) {
    final isRunning = _engine.isRunning;
    final canStart = isRunning || _window != _WishlistWindow.completed;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _autoRunStatus(),
                  style: TextStyle(
                    color: textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Gap(12),
              AppActionButton(
                icon: isRunning
                    ? Icons.stop_circle_outlined
                    : Icons.play_circle_outline_rounded,
                label: isRunning ? 'Stop' : 'Start',
                foregroundColor: isRunning
                    ? AppPalette.danger
                    : AppPalette.accent,
                onPressed: canStart ? _toggleEngine : null,
              ),
            ],
          ),
          if (_engine.activityLogs.isNotEmpty) ...[
            const Gap(12),
            AppActivityLog(logs: _engine.activityLogs),
          ],
        ],
      ),
    );
  }

  Widget _buildCourseRow(
    _CourseRow row,
    Color textPrimary,
    Color textSecondary,
  ) {
    final isSelected = _isInWishlist(row);
    final queued = _engine.queuedItem(row.code);
    final isFailed = queued?.status == WishlistQueueStatus.failed;
    final isPending =
        _pendingCodes.contains(row.code) ||
        queued?.status == WishlistQueueStatus.adding;
    final isActive = isSelected || queued != null;
    final highlightColor = isSelected
        ? AppPalette.accent
        : isFailed
        ? AppPalette.warning
        : AppPalette.primary;
    final label = queued == null ? null : (queued.note ?? 'Queued');

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        isHighlighted: isActive,
        highlightColor: highlightColor.withValues(alpha: 0.35),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    row.code,
                    style: TextStyle(
                      color: textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Gap(3),
                  Text(
                    row.name,
                    style: TextStyle(color: textSecondary, fontSize: 11),
                  ),
                  if (label != null) ...[
                    const Gap(3),
                    Text(
                      label,
                      style: TextStyle(
                        color: isFailed
                            ? AppPalette.warning
                            : AppPalette.primary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Gap(12),
            Text(
              '${row.credit} credits',
              style: TextStyle(
                color: textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(
              width: 48,
              child: isPending
                  ? const Center(child: AppSpinner(size: 18))
                  : _window == _WishlistWindow.completed
                  ? null
                  : SeatIconButton(
                      active: isActive,
                      activeColor: highlightColor,
                      icon: isActive
                          ? Icons.remove_circle_outline_rounded
                          : Icons.add_circle_outline_rounded,
                      tooltip: isSelected
                          ? 'Remove From Wishlist'
                          : queued != null
                          ? 'Remove From Queue'
                          : 'Add To Wishlist',
                      onTap: () => _onCourseTap(row),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
