import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:preconnect/api/api_client.dart';
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/app_storage.dart';
import 'package:preconnect/tools/storage_keys.dart';
import 'package:preconnect/api/profile.dart';
import 'package:preconnect/api/seat_status.dart';

class WishlistPage extends StatefulWidget {
  const WishlistPage({super.key});

  @override
  State<WishlistPage> createState() => _WishlistPageState();
}

class _WishlistPageState extends State<WishlistPage> {
  final ApiClient _client = ApiClient();
  bool _isLoading = true;
  bool _isPhaseCompleted = false;
  String? _errorMessage;
  String? _studentId;
  String? _portfolioId;
  String? _publicKey;
  List<dynamic> _wishlistCourses = [];
  List<dynamic> _offeredCourses = [];
  List<dynamic> _filteredOfferedCourses = [];
  Map<int, bool> _seatAvailabilityByCourseId = const <int, bool>{};
  final TextEditingController _searchController = TextEditingController();
  final List<dynamic> _batchQueue = [];
  String _searchQuery = '';

  ({String title, String message}) _errorDetails(String rawMessage) {
    var message = rawMessage;
    try {
      final startIndex = message.indexOf('{');
      final endIndex = message.lastIndexOf('}');
      if (startIndex != -1 && endIndex > startIndex) {
        final decoded = jsonDecode(message.substring(startIndex, endIndex + 1));
        if (decoded is Map && decoded['message'] != null) {
          message = decoded['message'].toString().replaceAll('\n', '').trim();
        }
      }
    } catch (_) {}

    if (message.contains('Wishlist has not been scheduled') ||
        message.contains('expired') ||
        message.contains('404')) {
      return (title: 'Wishlist Closed', message: message);
    }
    if (message.contains('SocketException') ||
        message.contains('Failed host lookup') ||
        message.contains('Connection failed') ||
        message.contains('Connection refused') ||
        message.contains('Connection timed out')) {
      return (
        title: 'You\'re Offline',
        message:
            'Wishlist requires an active connection to BRACU Connect. '
            'Check your internet and try again.',
      );
    }
    return (title: 'Advising Status', message: message);
  }

  Map<String, String> _buildHeaders() {
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json, text/plain, */*',
      if (!kIsWeb)
        'Referer': 'https://connect.bracu.ac.bd/student/advising/wish-list',
      if (!kIsWeb)
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 15; Pixel 9) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/150.0.0.0 Mobile Safari/537.36',
      'X-Advising-Session': _publicKey ?? '',
    };
  }

  @override
  void initState() {
    super.initState();
    _loadInitialData();
    _searchController.addListener(() {
      if (!mounted) return;
      setState(() {
        _searchQuery = _searchController.text;
      });
      _filterCourses(_searchQuery);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      _portfolioId = await resolvePortfolioId(
        prefs: AppStorage.instance,
        refreshProfile: () => ProfileService().getProfile(fromFetch: true),
      );
      _studentId = await AppStorage.instance.getString(StorageKeys.studentId);

      if (_studentId == null || _portfolioId == null) {
        throw Exception('Failed to resolve student portfolio profile.');
      }

      _publicKey = DateTime.now().millisecondsSinceEpoch.toString();
      String? sessionId = _portfolioId;

      try {
        final sessionRes = await _client.authenticatedGet(
          '${ApiConfig.connectApiBase}/adv/v1/advising/$_studentId/active-wishlist-sessions',
        );

        if (sessionRes.statusCode == 200) {
          final sessions = jsonDecode(sessionRes.body);
          if (sessions is List && sessions.isNotEmpty) {
            final session = sessions[0];
            sessionId = session['id']?.toString() ?? _portfolioId;
          }
        }

        if (sessionId != null) {
          await _client.authenticatedRequest(
            'POST',
            '${ApiConfig.connectApiBase}/adv/v1/advising/$sessionId/wishlist-session?publicKey=$_publicKey',
            body: '',
          );
        }
      } on ApiException catch (e) {
        if (e.statusCode == 412) {
          _isPhaseCompleted = true;
        } else {
          rethrow;
        }
      }

      await _refreshWishlistData();
      try {
        await SeatStatusService().preloadData();
        _rebuildSeatAvailability();
        if (mounted) setState(() {});
      } catch (_) {}
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _refreshWishlistData() async {
    if (_portfolioId == null) return;

    try {
      bool loadedFromCache = false;
      try {
        final wishlistRes = await _client.authenticatedGet(
          '${ApiConfig.connectApiBase}/adv/v1/wishlists/$_portfolioId',
          additionalHeaders: _buildHeaders(),
        );

        if (wishlistRes.statusCode == 200) {
          final data = jsonDecode(wishlistRes.body);
          if (data is List) {
            _wishlistCourses = data;
          } else if (data is Map && data['courses'] is List) {
            _wishlistCourses = data['courses'];
          }
          await AppStorage.instance.setString(
            'cached_wishlist_courses_$_portfolioId',
            jsonEncode(_wishlistCourses),
          );
        } else {
          loadedFromCache = true;
        }
      } catch (e) {
        loadedFromCache = true;
      }

      if (loadedFromCache) {
        final cachedJson = await AppStorage.instance.getString(
          'cached_wishlist_courses_$_portfolioId',
        );
        if (cachedJson != null && cachedJson.isNotEmpty) {
          _wishlistCourses = jsonDecode(cachedJson);
          _isPhaseCompleted = true;
        } else {
          throw Exception(
            'Wishlist has not been scheduled or has been expired. Please try after scheduled.',
          );
        }
      }

      try {
        final offeredRes = await _client.authenticatedGet(
          '${ApiConfig.connectApiBase}/adv/v1/wishlists/$_portfolioId/offered-courses',
          additionalHeaders: _buildHeaders(),
        );

        if (offeredRes.statusCode == 200) {
          final data = jsonDecode(offeredRes.body);
          if (data is List) {
            _offeredCourses = data;
          } else if (data is Map && data['courses'] is List) {
            _offeredCourses = data['courses'];
          }
          _rebuildSeatAvailability();
          _filterCourses(_searchController.text);
        } else {
          _isPhaseCompleted = true;
          _offeredCourses = [];
          _filteredOfferedCourses = [];
          _seatAvailabilityByCourseId = const <int, bool>{};
        }
      } catch (e) {
        _isPhaseCompleted = true;
        _offeredCourses = [];
        _filteredOfferedCourses = [];
        _seatAvailabilityByCourseId = const <int, bool>{};
      }

      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  void _filterCourses(String query) {
    if (query.isEmpty) {
      if (!mounted) return;
      setState(() {
        _filteredOfferedCourses = List.from(_offeredCourses);
      });
      return;
    }

    final lower = query.toLowerCase();
    if (!mounted) return;
    setState(() {
      _filteredOfferedCourses = _offeredCourses.where((c) {
        final code = (c['courseCode'] ?? c['code'] ?? '')
            .toString()
            .toLowerCase();
        final name = (c['courseName'] ?? c['name'] ?? '')
            .toString()
            .toLowerCase();
        return code.contains(lower) || name.contains(lower);
      }).toList();
    });
  }

  Future<void> _addCourse(dynamic course) async {
    if (_portfolioId == null) return;
    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });

    try {
      final int courseId = course['courseId'] as int;
      final int credits = course['courseCredit'] as int;

      final res = await _client.authenticatedRequest(
        'POST',
        '${ApiConfig.connectApiBase}/adv/v1/wishlists',
        body: jsonEncode({
          'courseId': courseId,
          'courseCredit': credits,
          'studentPortfolioId': int.parse(_portfolioId!),
        }),
        additionalHeaders: _buildHeaders(),
      );

      if (res.statusCode == 200 || res.statusCode == 201) {
        await _refreshWishlistData();
      } else {
        throw Exception('Failed to add course: ${res.body}');
      }
    } catch (e) {
      if (!mounted) return;
      showAppSnackBar(context, e.toString());
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _rebuildSeatAvailability() {
    final cached = SeatStatusService().cachedDetails;
    if (cached == null || cached.isEmpty) {
      _seatAvailabilityByCourseId = const <int, bool>{};
      return;
    }
    final foundSection = <int, bool>{};
    final hasSeats = <int, bool>{};
    for (final detail in cached.values) {
      foundSection[detail.courseId] = true;
      if (detail.capacity > detail.consumedSeat) {
        hasSeats[detail.courseId] = true;
      }
    }
    _seatAvailabilityByCourseId = {
      for (final courseId in foundSection.keys)
        courseId: hasSeats[courseId] ?? false,
    };
  }

  bool _hasSeatsForCourse(int courseId) {
    return _seatAvailabilityByCourseId[courseId] ?? true;
  }

  Future<void> _confirmDropCourse(dynamic course) async {
    final code = course['courseCode'] ?? course['code'] ?? '';
    await showBracuConfirmationWithActionDialog(
      context,
      icon: Icons.remove_circle_outline_rounded,
      title: 'Drop Course?',
      message: 'Are you sure you want to drop $code from your wishlist?',
      confirmLabel: 'Drop',
      cancelLabel: 'Cancel',
      confirmColor: BracuPalette.danger,
      onConfirm: () => _dropCourse(course),
    );
  }

  Future<void> _dropCourse(dynamic course) async {
    if (_portfolioId == null || _publicKey == null) return;
    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });

    try {
      final int courseId = course['courseId'] as int;
      final res = await _client.authenticatedRequest(
        'DELETE',
        '${ApiConfig.connectApiBase}/adv/v1/wishlists',
        body: jsonEncode({
          'courseId': courseId,
          'studentPortfolioId': int.parse(_portfolioId!),
        }),
        additionalHeaders: _buildHeaders(),
      );

      if (res.statusCode == 200 || res.statusCode == 204) {
        await _refreshWishlistData();
      } else {
        throw Exception('Failed to drop course: ${res.body}');
      }
    } catch (e) {
      if (!mounted) return;
      showAppSnackBar(context, e.toString());
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _executeBatchAdd() async {
    if (_batchQueue.isEmpty || _portfolioId == null) return;
    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });

    final List<Future<dynamic>> requests = [];
    for (final course in _batchQueue) {
      final int courseId = course['courseId'] as int;
      final int credits = course['courseCredit'] as int;
      requests.add(
        _client.authenticatedRequest(
          'POST',
          '${ApiConfig.connectApiBase}/adv/v1/wishlists',
          body: jsonEncode({
            'courseId': courseId,
            'courseCredit': credits,
            'studentPortfolioId': int.parse(_portfolioId!),
          }),
          additionalHeaders: _buildHeaders(),
        ),
      );
    }

    try {
      await Future.wait(requests);
      _batchQueue.clear();
      await _refreshWishlistData();
    } catch (e) {
      if (!mounted) return;
      showAppSnackBar(context, e.toString());
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final textPrimary = BracuPalette.textPrimary(context);
    final textSecondary = BracuPalette.textSecondary(context);

    if (_isLoading) {
      return const BracuPageScaffold(
        title: 'Advising',
        subtitle: 'Wishlist',
        icon: Icons.star_outline_rounded,
        body: Center(child: BracuLoading()),
      );
    }

    if (_errorMessage != null) {
      final error = _errorDetails(_errorMessage!);

      return BracuPageScaffold(
        title: 'Advising',
        subtitle: 'Wishlist',
        icon: Icons.star_outline_rounded,
        body: BracuErrorState(
          title: error.title,
          message: error.message,
          onRetry: _loadInitialData,
        ),
      );
    }

    return BracuPageScaffold(
      title: 'Advising',
      subtitle: 'Wishlist',
      icon: Icons.star_outline_rounded,
      actions: [
        IconButton(
          tooltip: 'Sync',
          icon: const Icon(Icons.sync_rounded),
          onPressed: _isLoading ? null : _loadInitialData,
        ),
        BracuRefreshButton(
          onPressed: _refreshWishlistData,
          isLoading: _isLoading,
        ),
      ],
      body: Column(
        children: [
          if (_isPhaseCompleted)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: BracuCard(
                backgroundColor: BracuPalette.info.withValues(alpha: 0.12),
                child: Row(
                  children: [
                    const Icon(
                      Icons.check_circle_rounded,
                      color: BracuPalette.info,
                    ),
                    const Gap(8),
                    Expanded(
                      child: Text(
                        'Wishlist phase completed already. Your selection has been finalized.',
                        style: TextStyle(
                          fontSize: 13,
                          color: textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (_batchQueue.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: BracuCard(
                backgroundColor: BracuPalette.info.withValues(alpha: 0.12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${_batchQueue.length} course(s) selected in batch queue.',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: textPrimary,
                        ),
                      ),
                    ),
                    BracuActionButton(
                      onPressed: _executeBatchAdd,
                      label: 'Add Batch',
                      outlined: false,
                      borderRadius: 10,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const Gap(8),
          Expanded(
            child: DefaultTabController(
              length: 2,
              child: Column(
                children: [
                  TabBar(
                    labelColor: BracuPalette.primary,
                    unselectedLabelColor: textSecondary,
                    indicatorColor: BracuPalette.primary,
                    tabs: const [
                      Tab(text: 'Current Wishlist'),
                      Tab(text: 'Offered Courses'),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _buildWishlistView(textPrimary, textSecondary),
                        _buildOfferedView(textPrimary, textSecondary),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWishlistView(Color textPrimary, Color textSecondary) {
    if (_wishlistCourses.isEmpty) {
      return BracuRefreshList(
        onRefresh: _refreshWishlistData,
        children: const [
          BracuEmptyCard(message: 'No courses in your wishlist.'),
        ],
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      itemCount: _wishlistCourses.length,
      itemBuilder: (context, index) {
        final course = _wishlistCourses[index];
        final code = course['courseCode'] ?? course['code'] ?? '';
        final name = course['courseName'] ?? course['name'] ?? '';
        final credits = course['courseCredit'] ?? course['credits'] ?? 3;

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: BracuCard(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$code - $name',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: textPrimary,
                          fontSize: 15,
                        ),
                      ),
                      const Gap(4),
                      Text(
                        'Credits: $credits',
                        style: TextStyle(color: textSecondary, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.remove_circle_outline_rounded,
                    color: _isPhaseCompleted
                        ? Colors.grey.withValues(alpha: 0.5)
                        : BracuPalette.danger,
                  ),
                  onPressed: _isPhaseCompleted
                      ? null
                      : () => _confirmDropCourse(course),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildOfferedView(Color textPrimary, Color textSecondary) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: BracuSearchField(
            controller: _searchController,
            hintText: 'Search course code or name...',
            query: _searchQuery,
          ),
        ),
        Expanded(
          child: _filteredOfferedCourses.isEmpty
              ? BracuRefreshList(
                  onRefresh: _refreshWishlistData,
                  children: [
                    BracuEmptyCard(
                      message: _searchQuery.trim().isEmpty
                          ? 'No offered courses are available.'
                          : 'No offered courses match your search.',
                    ),
                  ],
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: _filteredOfferedCourses.length,
                  itemBuilder: (context, index) {
                    final course = _filteredOfferedCourses[index];
                    final code = course['courseCode'] ?? course['code'] ?? '';
                    final name = course['courseName'] ?? course['name'] ?? '';
                    final credits =
                        course['courseCredit'] ?? course['credits'] ?? 3;
                    final isQueued = _batchQueue.contains(course);
                    final int courseId = course['courseId'] as int;
                    final hasSeats = _hasSeatsForCourse(courseId);

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: BracuCard(
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          '$code - $name',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: textPrimary,
                                            fontSize: 15,
                                          ),
                                        ),
                                      ),
                                      if (!hasSeats)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: BracuPalette.danger
                                                .withValues(alpha: 0.12),
                                            borderRadius: BorderRadius.circular(
                                              6,
                                            ),
                                          ),
                                          child: const Text(
                                            'No Seats',
                                            style: TextStyle(
                                              color: BracuPalette.danger,
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  const Gap(4),
                                  Text(
                                    'Credits: $credits',
                                    style: TextStyle(
                                      color: textSecondary,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: Icon(
                                isQueued
                                    ? Icons.check_box_rounded
                                    : Icons.add_box_outlined,
                                color: _isPhaseCompleted || !hasSeats
                                    ? Colors.grey.withValues(alpha: 0.5)
                                    : (isQueued
                                          ? BracuPalette.accent
                                          : BracuPalette.primary),
                              ),
                              onPressed: _isPhaseCompleted || !hasSeats
                                  ? null
                                  : () {
                                      setState(() {
                                        if (isQueued) {
                                          _batchQueue.remove(course);
                                        } else {
                                          _batchQueue.add(course);
                                        }
                                      });
                                    },
                            ),
                            IconButton(
                              icon: Icon(
                                Icons.flash_on_rounded,
                                color: _isPhaseCompleted || !hasSeats
                                    ? Colors.grey.withValues(alpha: 0.5)
                                    : BracuPalette.favorite,
                              ),
                              onPressed: _isPhaseCompleted || !hasSeats
                                  ? null
                                  : () => _addCourse(course),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
