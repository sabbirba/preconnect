import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:preconnect/api/preferences_store.dart';
import 'package:preconnect/api/auth.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/pages/home_tab.dart';
import 'google_sign_in_helper.dart';
import 'package:preconnect/pages/onboarding.dart';
import 'auth_service.dart';
import 'google_oauth_webview.dart';
import 'libsync_config.dart';
import 'library_card.dart';
import 'room_availability.dart';

class LibSyncPage extends StatefulWidget {
  const LibSyncPage({super.key});

  static Future<void> clearReservationCache() async {
    await _LibSyncPageState.clearReservationCache();
  }

  @override
  State<LibSyncPage> createState() => _LibSyncPageState();
}

class _LibSyncPageState extends State<LibSyncPage> {
  List<dynamic>? _reservationByYear;
  List<dynamic>? _recentReservations;
  List<dynamic>? _checkQuota;
  Map<String, dynamic>? _totalReservationCount;
  bool _loadingData = false;
  int? _selectedChartIndex;

  static List<dynamic>? _cachedReservationByYear;
  static List<dynamic>? _cachedRecentReservations;
  static List<dynamic>? _cachedCheckQuota;
  static Map<String, dynamic>? _cachedTotalReservationCount;
  static final List<DateTime> _fetchTimestamps = [];

  static Future<void> clearReservationCache() async {
    _cachedReservationByYear = null;
    _cachedRecentReservations = null;
    _cachedCheckQuota = null;
    _cachedTotalReservationCount = null;
    _fetchTimestamps.clear();

    final store = AppPreferencesStore();
    await store.remove('libsync_cache_reservation_by_year');
    await store.remove('libsync_cache_recent_reservations');
    await store.remove('libsync_cache_check_quota');
    await store.remove('libsync_cache_total_reservation_count');
  }

  @override
  void initState() {
    super.initState();
    _reservationByYear = _cachedReservationByYear;
    _recentReservations = _cachedRecentReservations;
    _checkQuota = _cachedCheckQuota;
    _totalReservationCount = _cachedTotalReservationCount;
    if (_reservationByYear != null) {
      _setDefaultChartIndex();
    }
    _loadDiskCache().then((_) {
      if (mounted) {
        setState(() {});
      }
    });
    LibSyncAuthService.instance.state.addListener(_onAuthStateChanged);
    _onAuthStateChanged();
  }

  Future<void> _loadDiskCache() async {
    if (_cachedReservationByYear != null) return;
    try {
      final store = AppPreferencesStore();
      final yearRaw = await store.getString(
        'libsync_cache_reservation_by_year',
      );
      final recentRaw = await store.getString(
        'libsync_cache_recent_reservations',
      );
      final quotaRaw = await store.getString('libsync_cache_check_quota');
      final countRaw = await store.getString(
        'libsync_cache_total_reservation_count',
      );

      if (yearRaw != null) {
        _cachedReservationByYear = jsonDecode(yearRaw) as List<dynamic>?;
      }
      if (recentRaw != null) {
        _cachedRecentReservations = jsonDecode(recentRaw) as List<dynamic>?;
      }
      if (quotaRaw != null) {
        _cachedCheckQuota = jsonDecode(quotaRaw) as List<dynamic>?;
      }
      if (countRaw != null) {
        _cachedTotalReservationCount =
            jsonDecode(countRaw) as Map<String, dynamic>?;
      }

      _reservationByYear = _cachedReservationByYear;
      _recentReservations = _cachedRecentReservations;
      _checkQuota = _cachedCheckQuota;
      _totalReservationCount = _cachedTotalReservationCount;
      if (_reservationByYear != null) {
        _setDefaultChartIndex();
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    LibSyncAuthService.instance.state.removeListener(_onAuthStateChanged);
    super.dispose();
  }

  void _onAuthStateChanged() {
    final status = LibSyncAuthService.instance.state.value.status;
    if (status == LibSyncAuthStatus.authenticated) {
      _loadReservationData();
    } else if (status == LibSyncAuthStatus.unauthenticated) {
      if (AuthService.isLoggingOut) return;
      _handleGoogleSignIn();
    }
  }

  void _setDefaultChartIndex() {
    final chartData = _getDynamicChartData();
    if (chartData.isEmpty) return;
    final now = DateTime.now();
    final shortMonths = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final currentMonthStr = shortMonths[now.month - 1].toLowerCase();
    final idx = chartData.indexWhere(
      (item) => item.name.toLowerCase().startsWith(currentMonthStr),
    );
    if (idx != -1) {
      _selectedChartIndex = idx;
    } else {
      _selectedChartIndex = chartData.length - 1;
    }
  }

  Future<void> _loadReservationData() async {
    final now = DateTime.now();
    _fetchTimestamps.removeWhere(
      (t) => now.difference(t) > const Duration(minutes: 1),
    );
    if (_fetchTimestamps.length >= 3) {
      return;
    }
    if (_loadingData) return;
    setState(() {
      _loadingData = true;
    });
    try {
      _fetchTimestamps.add(now);
      final dateStr =
          "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
      final results = await Future.wait([
        LibSyncAuthService.instance.fetchReservationByYear(now.year),
        LibSyncAuthService.instance.fetchRecentReservations(),
        LibSyncAuthService.instance.fetchCheckQuota(dateStr),
        LibSyncAuthService.instance.fetchTotalReservationCount(),
      ]);
      _cachedReservationByYear = results[0] as List<dynamic>?;
      _cachedRecentReservations =
          (results[1] as Map<String, dynamic>?)?['results'] as List<dynamic>?;
      _cachedCheckQuota = results[2] as List<dynamic>?;
      _cachedTotalReservationCount = results[3] as Map<String, dynamic>?;

      final store = AppPreferencesStore();
      if (_cachedReservationByYear != null) {
        unawaited(
          store.setString(
            'libsync_cache_reservation_by_year',
            jsonEncode(_cachedReservationByYear),
          ),
        );
      }
      if (_cachedRecentReservations != null) {
        unawaited(
          store.setString(
            'libsync_cache_recent_reservations',
            jsonEncode(_cachedRecentReservations),
          ),
        );
      }
      if (_cachedCheckQuota != null) {
        unawaited(
          store.setString(
            'libsync_cache_check_quota',
            jsonEncode(_cachedCheckQuota),
          ),
        );
      }
      if (_cachedTotalReservationCount != null) {
        unawaited(
          store.setString(
            'libsync_cache_total_reservation_count',
            jsonEncode(_cachedTotalReservationCount),
          ),
        );
      }

      if (mounted) {
        setState(() {
          _reservationByYear = _cachedReservationByYear;
          _recentReservations = _cachedRecentReservations;
          _checkQuota = _cachedCheckQuota;
          _totalReservationCount = _cachedTotalReservationCount;
          _setDefaultChartIndex();
        });
      }
    } catch (_) {
    } finally {
      if (mounted) {
        setState(() {
          _loadingData = false;
        });
      }
    }
  }

  Future<void> _handleGoogleSignIn() async {
    try {
      String? authCode;
      String? redirectUri;
      if (!kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.android ||
              defaultTargetPlatform == TargetPlatform.iOS)) {
        authCode = await Navigator.of(context).push<String>(
          MaterialPageRoute(
            builder: (context) => const GoogleOAuthWebViewPage(),
          ),
        );
        redirectUri = LibSyncConfig.googleRedirectUri;
      } else {
        final googleSignIn = GoogleSignIn(
          serverClientId: LibSyncConfig.googleClientId,
          scopes: LibSyncConfig.googleScopes.isEmpty
              ? ['email', 'profile']
              : LibSyncConfig.googleScopes.split(' '),
        );
        final account = await googleSignIn.signIn();
        authCode = account?.serverAuthCode;
      }

      if (authCode != null) {
        await LibSyncAuthService.instance.authenticateWithCode(
          authCode,
          redirectUri: redirectUri,
        );
      } else {
        if (mounted) {
          showAppSnackBar(context, 'Sign in cancelled.');
          Navigator.of(context).maybePop();
        }
      }
    } catch (e) {
      if (mounted) {
        showAppSnackBar(
          context,
          'Google Sign In failed: ${e.toString().replaceAll('Exception: ', '')}',
        );
        Navigator.of(context).maybePop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<LibSyncAuthState>(
      valueListenable: LibSyncAuthService.instance.state,
      builder: (context, state, child) {
        switch (state.status) {
          case LibSyncAuthStatus.loading:
            return const BracuPageScaffold(
              title: 'BRACU Libsync',
              subtitle: 'Ayesha Abed Library',
              icon: Icons.local_library_outlined,
              body: Center(child: BracuLoading()),
            );
          case LibSyncAuthStatus.error:
            return BracuPageScaffold(
              title: 'BRACU Libsync',
              subtitle: 'Ayesha Abed Library',
              icon: Icons.local_library_outlined,
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        size: 64,
                        color: Colors.red,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Authentication Error',
                        style: TextStyle(
                          color: BracuPalette.textPrimary(context),
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _getFriendlyErrorMessage(state.errorMessage),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: BracuPalette.textSecondary(context),
                        ),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: () => LibSyncAuthService.instance.logout(),
                        child: const Text('Sign In Again'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          case LibSyncAuthStatus.unauthenticated:
            return const BracuPageScaffold(
              title: 'BRACU Libsync',
              subtitle: 'Ayesha Abed Library',
              icon: Icons.local_library_outlined,
              body: Center(child: BracuLoading()),
            );
          case LibSyncAuthStatus.authenticated:
            final profile = state.profile;
            if (profile == null) return const SizedBox.shrink();

            return BracuPageScaffold(
              title: 'BRACU Libsync',
              subtitle: 'Ayesha Abed Library',
              icon: Icons.local_library_outlined,
              actions: [
                IconButton(
                  icon: const Icon(Icons.logout),
                  onPressed: () async {
                    final logoutContext = context;
                    if (!logoutContext.mounted) return;
                    final confirmed = await showBracuConfirmationWithActionDialog(
                      context,
                      icon: Icons.logout,
                      title: 'Confirm Sign Out?',
                      message:
                          'Are you sure you want to sign out from BRACU Libsync?',
                      confirmLabel: 'Sign Out',
                      confirmColor: BracuPalette.danger,
                      onConfirm: () async {
                        LibSyncAuthService.instance.state.removeListener(
                          _onAuthStateChanged,
                        );
                        await LibSyncAuthService.instance.logout();
                      },
                    );
                    if (confirmed == true && logoutContext.mounted) {
                      final globallyLoggedIn = await AuthService().isLoggedIn();
                      if (logoutContext.mounted) {
                        if (globallyLoggedIn) {
                          if (Navigator.of(logoutContext).canPop()) {
                            Navigator.of(logoutContext).pop();
                          } else {
                            HomeTabRegistry.setActive(HomeTab.dashboard);
                          }
                        } else {
                          Navigator.of(logoutContext).pushAndRemoveUntil(
                            MaterialPageRoute<void>(
                              builder: (_) => const OnboardingPage(),
                            ),
                            (route) => false,
                          );
                        }
                      }
                    }
                  },
                ),
              ],
              body: BracuRefreshList(
                onRefresh: () async {
                  await LibSyncAuthService.instance.initialize();
                  await _loadReservationData();
                },
                children: [
                  LibraryCard(profile: profile),
                  const SizedBox(height: 18),
                  const BracuSectionTitle(title: 'Overview'),
                  const SizedBox(height: 10),
                  () {
                    final reservationByYear = _reservationByYear;
                    final totalReservationCount = _totalReservationCount;
                    if (totalReservationCount == null &&
                        (reservationByYear == null ||
                            reservationByYear.isEmpty ||
                            !reservationByYear.any(
                              (monthData) => _hasReservations(monthData),
                            ))) {
                      return const SizedBox.shrink();
                    }
                    return BracuCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (totalReservationCount != null)
                            _StatsGrid(stats: totalReservationCount),
                          if (reservationByYear != null &&
                              reservationByYear.any(
                                (monthData) => _hasReservations(monthData),
                              )) ...[
                            const SizedBox(height: 14),
                            Divider(
                              height: 1,
                              thickness: 1,
                              color: BracuPalette.textSecondary(
                                context,
                              ).withValues(alpha: 0.12),
                            ),
                            const SizedBox(height: 14),
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final chartData = _getDynamicChartData();
                                return GestureDetector(
                                  onTapDown: (details) {
                                    if (chartData.isEmpty) return;
                                    final double localX =
                                        details.localPosition.dx;
                                    const double sideMargin = 16.0;
                                    final double chartWidth =
                                        constraints.maxWidth - 2 * sideMargin;
                                    final double stepX = chartData.length > 1
                                        ? chartWidth / (chartData.length - 1)
                                        : chartWidth;
                                    final double relativeX =
                                        localX - sideMargin;
                                    final int rawIndex = (relativeX / stepX)
                                        .round();
                                    final int index = rawIndex.clamp(
                                      0,
                                      chartData.length - 1,
                                    );
                                    setState(() {
                                      _selectedChartIndex = index;
                                    });
                                  },
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints.tightFor(
                                      height: 140,
                                    ),
                                    child: CustomPaint(
                                      size: Size.infinite,
                                      painter: _ChartPainter(
                                        chartData: chartData,
                                        selectedIndex: _selectedChartIndex,
                                        isDark:
                                            Theme.of(context).brightness ==
                                            Brightness.dark,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        ],
                      ),
                    );
                  }(),
                  const SizedBox(height: 18),
                  BracuActionBannerCard(
                    icon: Icons.calendar_month_outlined,
                    title: 'Room Availability',
                    subtitle: 'Book available rooms and slots',
                    onTap: () async {
                      final booked = await Navigator.of(context).push<bool>(
                        MaterialPageRoute(
                          builder: (context) => const RoomAvailabilityPage(),
                        ),
                      );
                      if (booked == true) {
                        if (context.mounted) {
                          showAppSnackBar(context, 'Booking successful!');
                        }
                      }
                      _loadReservationData();
                    },
                  ),
                  () {
                    final checkQuota = _checkQuota;
                    final recentReservations = _recentReservations;
                    if (_loadingData && checkQuota == null) {
                      return const BracuLoading();
                    }
                    final hasQuota =
                        checkQuota != null && checkQuota.isNotEmpty;
                    final hasRecent =
                        recentReservations != null &&
                        recentReservations.isNotEmpty;
                    if (!hasQuota && !hasRecent) {
                      return const SizedBox.shrink();
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 18),
                        if (hasQuota) ...[
                          const BracuSectionTitle(title: 'Daily Quota'),
                          const SizedBox(height: 10),
                          _QuotaCard(quota: checkQuota),
                          const SizedBox(height: 18),
                        ],
                        if (recentReservations != null) ...[
                          const BracuSectionTitle(title: 'Recent Reservations'),
                          const SizedBox(height: 10),
                          _RecentReservationsList(
                            reservations: recentReservations,
                            onRefresh: _loadReservationData,
                          ),
                        ],
                      ],
                    );
                  }(),
                  const SizedBox(height: 12),
                ],
              ),
            );
        }
      },
    );
  }

  bool _hasReservations(dynamic monthData) {
    if (monthData is! Map<String, dynamic>) return false;
    return monthData.entries.any(
      (entry) => entry.key != 'month' && entry.value is num && entry.value > 0,
    );
  }

  int _getReservationsCount(dynamic monthData) {
    if (monthData is! Map<String, dynamic>) return 0;
    return monthData.entries
        .where((entry) => entry.key != 'month' && entry.value is num)
        .fold<int>(0, (sum, entry) => sum + (entry.value as num).toInt());
  }

  List<_MonthChartData> _getDynamicChartData() {
    if (_reservationByYear == null) return [];
    final List<_MonthChartData> items = [];

    for (int i = 0; i < _reservationByYear!.length; i++) {
      final monthData = _reservationByYear![i];
      final monthStr = monthData['month']?.toString() ?? '';
      if (monthStr.isNotEmpty) {
        final count = _getReservationsCount(monthData);
        items.add(
          _MonthChartData(name: monthStr, count: count, chronologicalIndex: i),
        );
      }
    }
    return items;
  }

  String _getFriendlyErrorMessage(String? error) {
    if (error == null || error.isEmpty) {
      return 'An unexpected error occurred. Please try again.';
    }
    final lower = error.toLowerCase();
    if (lower.contains('socket') ||
        lower.contains('network') ||
        lower.contains('failed to connect') ||
        lower.contains('timeout')) {
      return 'Could not connect to the library system. Please check your internet connection.';
    }
    if (lower.contains('401') ||
        lower.contains('unauthorized') ||
        lower.contains('token') ||
        lower.contains('cookie')) {
      return 'Your session has expired. Please sign in again.';
    }
    if (lower.contains('403') || lower.contains('forbidden')) {
      return 'Access denied. Please contact the library administrator.';
    }
    if (lower.contains('50') ||
        lower.contains('server error') ||
        lower.contains('internal')) {
      return 'The library server is temporarily unavailable. Please try again later.';
    }
    return 'Could not complete authentication. Please try again.\nError: $error';
  }
}

class _QuotaCard extends StatelessWidget {
  const _QuotaCard({required this.quota});
  final List<dynamic> quota;

  @override
  Widget build(BuildContext context) {
    return BracuCard(
      child: Column(
        children: List.generate(quota.length, (index) {
          final q = quota[index];
          final title = (q['title'] ?? '').toString();
          final allowed = int.tryParse(q['allowed']?.toString() ?? '0') ?? 0;
          final available =
              int.tryParse(q['available']?.toString() ?? '0') ?? 0;
          final isLast = index == quota.length - 1;

          final percentage = allowed == 0 ? 0.0 : (available / allowed);

          return Padding(
            padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: BracuPalette.textPrimary(context),
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      '$available / $allowed available',
                      style: TextStyle(
                        color: BracuPalette.textSecondary(context),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                if (allowed > 0) ...[
                  const SizedBox(height: 6),
                  SimpleProgressBar(
                    value: percentage.clamp(0.0, 1.0),
                    color: BracuPalette.primary,
                  ),
                ],
                if (!isLast) const SizedBox(height: 12),
                if (!isLast)
                  Divider(
                    height: 1,
                    color: BracuPalette.textSecondary(
                      context,
                    ).withValues(alpha: 0.16),
                  ),
              ],
            ),
          );
        }),
      ),
    );
  }
}

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.stats});
  final Map<String, dynamic> stats;

  @override
  Widget build(BuildContext context) {
    final double total =
        double.tryParse(stats['total_slots']?.toString() ?? '0') ?? 0.0;
    final double confirmed =
        double.tryParse(stats['total_confirmed']?.toString() ?? '0') ?? 0.0;
    final double cancelled =
        double.tryParse(stats['total_cancelled']?.toString() ?? '0') ?? 0.0;
    final int today =
        int.tryParse(stats['today_reserved_slots']?.toString() ?? '0') ?? 0;

    final confirmedRatio = total == 0 ? 0.0 : confirmed / total;
    final cancelledRatio = total == 0 ? 0.0 : cancelled / total;
    final todayRatio = total == 0 ? 0.0 : today / total;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _BarItem(
                label: 'Confirmed',
                value: confirmedRatio,
                count: confirmed.toInt(),
                color: Colors.green,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _BarItem(
                label: 'Cancelled',
                value: cancelledRatio,
                count: cancelled.toInt(),
                color: Colors.red,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _BarItem(
                label: 'Total',
                value: total == 0 ? 0.0 : 1.0,
                count: total.toInt(),
                color: const Color(0xFF1E6BE3),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _BarItem(
                label: 'Today',
                value: todayRatio,
                count: today,
                color: Colors.orange,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _BarItem extends StatelessWidget {
  const _BarItem({
    required this.label,
    required this.value,
    required this.count,
    required this.color,
  });

  final String label;
  final double value;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                color: BracuPalette.textSecondary(context),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              '$count',
              style: TextStyle(
                color: BracuPalette.textPrimary(context),
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        SimpleProgressBar(value: value, color: color),
      ],
    );
  }
}

class _RecentReservationsList extends StatefulWidget {
  const _RecentReservationsList({
    required this.reservations,
    required this.onRefresh,
  });

  final List<dynamic> reservations;
  final VoidCallback onRefresh;

  @override
  State<_RecentReservationsList> createState() =>
      _RecentReservationsListState();
}

class _RecentReservationsListState extends State<_RecentReservationsList> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    if (widget.reservations.isEmpty) {
      return const BracuCard(
        child: Center(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: BracuEmptyState(message: 'No recent reservations found'),
          ),
        ),
      );
    }

    final textSecondary = BracuPalette.textSecondary(context);
    final textPrimary = BracuPalette.textPrimary(context);

    final showCount = _expanded ? widget.reservations.length : 3;
    final visibleReservations = widget.reservations.take(showCount).toList();

    return Column(
      children: [
        ...visibleReservations.map((res) {
          final room = (res['room_no'] ?? {})['room_no'] ?? 'N/A';
          final category = (res['room_no'] ?? {})['room_cat'] ?? 'N/A';
          final date = formatDate(res['reserve_start_date']?.toString());
          final code = res['reservation_code']?.toString() ?? 'N/A';
          final uniqueToken = res['unique_token']?.toString() ?? '';
          final status = (res['status'] ?? '').toString();

          Color statusColor;
          switch (status.toLowerCase()) {
            case 'confirmed':
            case 'presented':
              statusColor = Colors.green;
              break;
            case 'cancelled':
              statusColor = Colors.red;
              break;
            default:
              statusColor = Colors.orange;
          }

          final cardBorder = statusColor.withValues(alpha: 0.35);

          return Container(
            margin: const EdgeInsets.symmetric(vertical: 6),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: cardBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Icon(
                            Icons.bookmark_outline_rounded,
                            size: 18,
                            color: statusColor,
                          ),
                          const SizedBox(width: 10),
                          Flexible(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                GestureDetector(
                                  onTap: () => copyToClipboard(context, code),
                                  child: Text(
                                    code,
                                    style: TextStyle(
                                      color: textPrimary,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 15,
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                GestureDetector(
                                  onTap: () => copyToClipboard(context, code),
                                  child: Icon(
                                    Icons.copy_rounded,
                                    size: 15,
                                    color: textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      room,
                      style: TextStyle(
                        color: textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                      textAlign: TextAlign.right,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _InfoLine(
                  label: 'Category',
                  value: category,
                  isLabelBold: true,
                  isValueBold: true,
                ),
                const SizedBox(height: 8),
                _InfoLine(
                  label: 'Date',
                  value: date,
                  isLabelBold: false,
                  isValueBold: false,
                ),
                const SizedBox(height: 6),
                _InfoLine(
                  label: 'Time Slot',
                  value: _formatSlot(res['slot']),
                  isLabelBold: true,
                  isValueBold: true,
                ),
                const SizedBox(height: 6),
                _InfoLine(
                  label: 'Status',
                  value: status,
                  isLabelBold: true,
                  isValueBold: true,
                  valueColor: statusColor,
                ),
                if (status.toLowerCase() == 'confirmed') ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            side: BorderSide(
                              color: Colors.red.withValues(alpha: 0.4),
                              width: 1.2,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                          onPressed: () async {
                            final confirm =
                                await showBracuConfirmationWithActionDialog(
                                  context,
                                  icon: Icons.cancel_outlined,
                                  title: 'Cancel Booking?',
                                  message:
                                      'Are you sure you want to cancel this booking?',
                                  confirmLabel: 'Cancel',
                                  confirmColor: Colors.red,
                                  onConfirm: () async {},
                                );
                            if (confirm == true) {
                              if (!context.mounted) return;
                              showDialog(
                                context: context,
                                barrierDismissible: false,
                                builder: (context) => const Center(
                                  child: CircularProgressIndicator(),
                                ),
                              );
                              try {
                                if (uniqueToken.isNotEmpty) {
                                  await LibSyncAuthService.instance
                                      .cancelReservation(uniqueToken);
                                  if (context.mounted) {
                                    Navigator.of(context).pop();
                                    showAppSnackBar(
                                      context,
                                      'Reservation cancelled',
                                    );
                                    widget.onRefresh();
                                  }
                                }
                              } catch (e) {
                                if (context.mounted) {
                                  Navigator.of(context).pop();
                                  showAppSnackBar(
                                    context,
                                    e.toString().replaceAll('Exception: ', ''),
                                  );
                                }
                              }
                            }
                          },
                          child: const Text(
                            'Cancel',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: BracuPalette.primary,
                            side: BorderSide(
                              color: BracuPalette.primary.withValues(
                                alpha: 0.4,
                              ),
                              width: 1.2,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                          onPressed: () async {
                            final confirm =
                                await showBracuConfirmationWithActionDialog(
                                  context,
                                  icon: Icons.location_on_outlined,
                                  title: 'Confirm Check In?',
                                  message:
                                      'Are you at the library and ready to check in?',
                                  confirmLabel: 'Check In',
                                  confirmColor: BracuPalette.primary,
                                  onConfirm: () async {},
                                );
                            if (confirm != true) return;
                            if (!context.mounted) return;
                            showDialog(
                              context: context,
                              barrierDismissible: false,
                              builder: (context) => const Center(
                                child: CircularProgressIndicator(),
                              ),
                            );
                            try {
                              final intCode = int.tryParse(code);
                              if (intCode != null) {
                                final message = await LibSyncAuthService
                                    .instance
                                    .checkInAttendance(intCode);
                                if (context.mounted) {
                                  Navigator.of(context).pop();
                                  showAppSnackBar(context, message);
                                  widget.onRefresh();
                                }
                              }
                            } catch (e) {
                              if (context.mounted) {
                                Navigator.of(context).pop();
                                showAppSnackBar(
                                  context,
                                  e.toString().replaceAll('Exception: ', ''),
                                );
                              }
                            }
                          },
                          child: const Text(
                            'Check In',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          );
        }),
        if (widget.reservations.length > 3)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: buildCenteredOutlinedActionButton(
              label: _expanded ? 'Show Less' : 'Show More',
              onPressed: () {
                setState(() {
                  _expanded = !_expanded;
                });
              },
            ),
          ),
      ],
    );
  }

  String _formatSlot(dynamic slots) {
    if (slots is List && slots.isNotEmpty) {
      final slot = slots.first;
      final start = (slot['start_time'] ?? '').toString();
      final end = (slot['end_time'] ?? '').toString();
      return '${formatTime(start)} - ${formatTime(end)}';
    }
    return 'N/A';
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({
    required this.label,
    required this.value,
    this.isValueBold = false,
    this.isLabelBold = false,
    this.valueColor,
  });

  final String label;
  final String value;
  final bool isValueBold;
  final bool isLabelBold;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final textSecondary = BracuPalette.textSecondary(context);
    final textPrimary = BracuPalette.textPrimary(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: Text(
              label,
              style: TextStyle(
                color: textSecondary,
                fontWeight: isLabelBold ? FontWeight.w700 : FontWeight.w500,
                fontSize: 14,
              ),
              textAlign: TextAlign.left,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 6,
            child: Text(
              value,
              style: TextStyle(
                color: valueColor ?? textPrimary,
                fontWeight: isValueBold ? FontWeight.w700 : FontWeight.w500,
                fontSize: 14,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChartPainter extends CustomPainter {
  _ChartPainter({
    required this.chartData,
    required this.selectedIndex,
    required this.isDark,
  });

  final List<_MonthChartData> chartData;
  final int? selectedIndex;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final axisPaint = Paint()
      ..color = isDark ? Colors.white30 : Colors.black87
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    final barPaint = Paint()
      ..color = const Color(0xFFF05A28)
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final highlightPaint = Paint()
      ..color = const Color(0xFFF05A28)
      ..strokeWidth = 5.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    const double sideMargin = 16.0;
    const double bottomMargin = 20.0;

    final double chartWidth = size.width - 2 * sideMargin;
    final double chartHeight = size.height - bottomMargin - 15.0;

    final double maxVal = chartData.isEmpty
        ? 0.0
        : chartData
              .map((e) => e.count.toDouble())
              .reduce((a, b) => a > b ? a : b);

    canvas.drawLine(
      const Offset(sideMargin, 10.0),
      Offset(sideMargin, size.height - bottomMargin),
      axisPaint,
    );

    canvas.drawLine(
      Offset(sideMargin, size.height - bottomMargin),
      Offset(size.width - sideMargin, size.height - bottomMargin),
      axisPaint,
    );

    final yTicks = [0.0, 1.0];
    for (final tick in yTicks) {
      final double y = size.height - bottomMargin - (tick * chartHeight);
      canvas.drawLine(
        Offset(sideMargin - 4.0, y),
        Offset(sideMargin, y),
        axisPaint,
      );
      final labelText = tick == 0.0
          ? '0'
          : (maxVal > 0 ? maxVal.toInt().toString() : '1');
      final tp = TextPainter(
        text: TextSpan(
          text: labelText,
          style: TextStyle(
            color: isDark ? Colors.white70 : Colors.black87,
            fontSize: 9,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      tp.layout();
      tp.paint(canvas, Offset(sideMargin - tp.width - 4.0, y - tp.height / 2));
    }

    if (chartData.isEmpty) return;

    final double stepX = chartData.length > 1
        ? chartWidth / (chartData.length - 1)
        : chartWidth;

    for (int i = 0; i < chartData.length; i++) {
      final double x = chartData.length > 1
          ? sideMargin + (i * stepX)
          : sideMargin + chartWidth / 2;
      final double y = size.height - bottomMargin;

      canvas.drawLine(Offset(x, y), Offset(x, y + 4.0), axisPaint);

      final tp = TextPainter(
        text: TextSpan(
          text: chartData[i].name,
          style: TextStyle(
            color: isDark ? Colors.white70 : Colors.black87,
            fontSize: 8.5,
            fontWeight: FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      tp.layout();
      tp.paint(canvas, Offset(x - tp.width / 2, y + 6.0));

      final double val = maxVal == 0.0 ? 0.0 : chartData[i].count / maxVal;
      if (val > 0) {
        final double barY = y - (val * chartHeight);
        final isSelected = selectedIndex == i;
        canvas.drawLine(
          Offset(x, y),
          Offset(x, barY),
          isSelected ? highlightPaint : barPaint,
        );
      }
    }

    if (selectedIndex != null &&
        selectedIndex! >= 0 &&
        selectedIndex! < chartData.length) {
      final int i = selectedIndex!;
      final double x = chartData.length > 1
          ? sideMargin + (i * stepX)
          : sideMargin + chartWidth / 2;
      final double val = maxVal == 0.0 ? 0.0 : chartData[i].count / maxVal;
      final double barY = size.height - bottomMargin - (val * chartHeight);

      final tooltipText = '${chartData[i].name}: ${chartData[i].count}';
      final tp = TextPainter(
        text: const TextSpan(text: ''),
        textDirection: TextDirection.ltr,
      );
      final span = TextSpan(
        text: tooltipText,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      );
      tp.text = span;
      tp.layout();

      final double tooltipWidth = tp.width + 12;
      final double tooltipHeight = tp.height + 8;

      double tooltipX = x - tooltipWidth / 2;
      if (tooltipX < sideMargin) tooltipX = sideMargin;
      if (tooltipX + tooltipWidth > size.width) {
        tooltipX = size.width - tooltipWidth;
      }
      final double tooltipY = (barY - tooltipHeight - 6).clamp(
        4.0,
        size.height,
      );

      final rrect = RRect.fromRectAndRadius(
        Rect.fromLTWH(tooltipX, tooltipY, tooltipWidth, tooltipHeight),
        const Radius.circular(6),
      );

      final tooltipBgPaint = Paint()..color = const Color(0xFFF05A28);
      canvas.drawRRect(rrect, tooltipBgPaint);
      tp.paint(canvas, Offset(tooltipX + 6, tooltipY + 4));
    }
  }

  @override
  bool shouldRepaint(covariant _ChartPainter oldDelegate) {
    return oldDelegate.chartData != chartData ||
        oldDelegate.selectedIndex != selectedIndex ||
        oldDelegate.isDark != isDark;
  }
}

class _MonthChartData {
  final String name;
  final int count;
  final int chronologicalIndex;

  _MonthChartData({
    required this.name,
    required this.count,
    required this.chronologicalIndex,
  });
}
