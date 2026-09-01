import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:preconnect/api/api_client.dart';
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/app_storage.dart';
import 'package:preconnect/api/profile.dart';

List<Map<String, dynamic>> parseWishlistCourseList(String body) {
  final decoded = jsonDecode(body);
  if (decoded is! List) {
    throw const FormatException('Invalid Wishlist course response.');
  }
  return decoded
      .map((item) {
        if (item is! Map) {
          throw const FormatException('Invalid Wishlist course record.');
        }
        final course = item.cast<String, dynamic>();
        if (course['courseId'] is! num ||
            '${course['courseCode'] ?? ''}'.trim().isEmpty ||
            '${course['name'] ?? ''}'.trim().isEmpty ||
            course['courseCredit'] is! num) {
          throw const FormatException('Incomplete Wishlist course record.');
        }
        return course;
      })
      .toList(growable: false);
}

int wishlistCourseId(Map<String, dynamic> course) =>
    (course['courseId'] as num).toInt();

bool wishlistContainsCourse(
  Iterable<Map<String, dynamic>> courses,
  Map<String, dynamic> course,
) {
  final courseId = wishlistCourseId(course);
  return courses.any((item) => wishlistCourseId(item) == courseId);
}

List<Map<String, dynamic>> mergeWishlistCourseOptions(
  Iterable<Map<String, dynamic>> selectedCourses,
  Iterable<Map<String, dynamic>> offeredCourses,
) {
  final coursesById = <int, Map<String, dynamic>>{};
  for (final course in selectedCourses) {
    coursesById[wishlistCourseId(course)] = course;
  }
  for (final course in offeredCourses) {
    coursesById.putIfAbsent(wishlistCourseId(course), () => course);
  }
  return coursesById.values.toList(growable: false);
}

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
  String? _portfolioId;
  String? _publicKey;
  List<Map<String, dynamic>> _wishlistCourses = [];
  List<Map<String, dynamic>> _offeredCourses = [];
  List<Map<String, dynamic>> _filteredOfferedCourses = [];
  final TextEditingController _searchController = TextEditingController();
  final List<Map<String, dynamic>> _batchQueue = [];
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

      if (_portfolioId == null) {
        throw Exception('Failed to resolve student portfolio profile.');
      }

      _publicKey = DateTime.now().millisecondsSinceEpoch.toString();

      try {
        await _client.authenticatedRequest(
          'POST',
          '${ApiConfig.connectApiBase}${ApiConfig.wishlistSessionPath(_portfolioId!, _publicKey!)}',
          body: '',
        );
      } on ApiException catch (e) {
        if (e.statusCode == 412) {
          _isPhaseCompleted = true;
        } else {
          rethrow;
        }
      }

      await _refreshWishlistData();
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
      final wishlistRes = await _client.authenticatedGet(
        '${ApiConfig.connectApiBase}${ApiConfig.wishlistCoursesPath(_portfolioId!)}',
        additionalHeaders: _buildHeaders(),
        bypassCache: true,
      );
      final offeredRes = await _client.authenticatedGet(
        '${ApiConfig.connectApiBase}${ApiConfig.wishlistOfferedCoursesPath(_portfolioId!)}',
        additionalHeaders: _buildHeaders(),
        bypassCache: true,
      );

      _wishlistCourses = parseWishlistCourseList(wishlistRes.body);
      _offeredCourses = mergeWishlistCourseOptions(
        _wishlistCourses,
        parseWishlistCourseList(offeredRes.body),
      );
      _filterCourses(_searchController.text);

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
        final code = c['courseCode'].toString().toLowerCase();
        final name = c['name'].toString().toLowerCase();
        return code.contains(lower) || name.contains(lower);
      }).toList();
    });
  }

  Future<void> _addCourse(Map<String, dynamic> course) async {
    if (_portfolioId == null) return;
    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });

    try {
      final int courseId = (course['courseId'] as num).toInt();
      final int credits = (course['courseCredit'] as num).toInt();

      final res = await _client.authenticatedRequest(
        'POST',
        '${ApiConfig.connectApiBase}${ApiConfig.wishlistMutationPath}',
        body: jsonEncode({
          'courseId': courseId,
          'courseCredit': credits,
          'studentPortfolioId': int.parse(_portfolioId!),
        }),
        additionalHeaders: _buildHeaders(),
        acceptedStatusCodes: const <int>{200, 201},
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

  Future<void> _confirmDropCourse(Map<String, dynamic> course) async {
    final code = course['courseCode'];
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

  Future<void> _dropCourse(Map<String, dynamic> course) async {
    if (_portfolioId == null || _publicKey == null) return;
    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });

    try {
      final int courseId = (course['courseId'] as num).toInt();
      final res = await _client.authenticatedRequest(
        'DELETE',
        '${ApiConfig.connectApiBase}${ApiConfig.wishlistMutationPath}',
        body: jsonEncode({
          'courseId': courseId,
          'studentPortfolioId': int.parse(_portfolioId!),
        }),
        additionalHeaders: _buildHeaders(),
        acceptedStatusCodes: const <int>{200, 204},
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

    try {
      for (final course in List<Map<String, dynamic>>.from(_batchQueue)) {
        final int courseId = (course['courseId'] as num).toInt();
        final int credits = (course['courseCredit'] as num).toInt();
        await _client.authenticatedRequest(
          'POST',
          '${ApiConfig.connectApiBase}${ApiConfig.wishlistMutationPath}',
          body: jsonEncode({
            'courseId': courseId,
            'courseCredit': credits,
            'studentPortfolioId': int.parse(_portfolioId!),
          }),
          additionalHeaders: _buildHeaders(),
          acceptedStatusCodes: const <int>{200, 201},
        );
      }
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
        final code = course['courseCode'];
        final name = course['name'];
        final credits = course['courseCredit'];

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
                    final code = course['courseCode'];
                    final name = course['name'];
                    final credits = course['courseCredit'];
                    final isWishlisted = wishlistContainsCourse(
                      _wishlistCourses,
                      course,
                    );
                    final isQueued = wishlistContainsCourse(
                      _batchQueue,
                      course,
                    );
                    final isSelected = isWishlisted || isQueued;

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
                                isSelected
                                    ? Icons.check_box_rounded
                                    : Icons.add_box_outlined,
                                color: _isPhaseCompleted
                                    ? Colors.grey.withValues(alpha: 0.5)
                                    : (isSelected
                                          ? BracuPalette.accent
                                          : BracuPalette.primary),
                              ),
                              onPressed: _isPhaseCompleted || isWishlisted
                                  ? null
                                  : () {
                                      setState(() {
                                        if (isQueued) {
                                          _batchQueue.removeWhere(
                                            (item) =>
                                                wishlistCourseId(item) ==
                                                wishlistCourseId(course),
                                          );
                                        } else {
                                          _batchQueue.add(course);
                                        }
                                      });
                                    },
                            ),
                            IconButton(
                              icon: Icon(
                                Icons.flash_on_rounded,
                                color: _isPhaseCompleted
                                    ? Colors.grey.withValues(alpha: 0.5)
                                    : BracuPalette.favorite,
                              ),
                              onPressed: _isPhaseCompleted || isWishlisted
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
