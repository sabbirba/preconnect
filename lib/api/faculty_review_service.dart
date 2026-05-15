import 'dart:convert';
import 'dart:async';

import 'package:preconnect/api/api_client.dart';
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/api/app_preferences_store.dart';

class FacultyRatingStats {
  const FacultyRatingStats({
    required this.reviewsTotal,
    required this.overall,
    required this.teaching,
    required this.fairness,
    required this.behavior,
  });

  final int reviewsTotal;
  final double overall;
  final double teaching;
  final double fairness;
  final double behavior;

  factory FacultyRatingStats.fromJson(Map<String, dynamic> json) {
    return FacultyRatingStats(
      reviewsTotal: (json['reviewsTotal'] as num?)?.toInt() ?? 0,
      overall: (json['overall'] as num?)?.toDouble() ?? 0,
      teaching: (json['teaching'] as num?)?.toDouble() ?? 0,
      fairness: (json['fairness'] as num?)?.toDouble() ?? 0,
      behavior: (json['behavior'] as num?)?.toDouble() ?? 0,
    );
  }
}

class FacultySummary {
  const FacultySummary({
    required this.facultyId,
    required this.initial,
    required this.name,
    required this.email,
    required this.courses,
    required this.stats,
    this.reviewSummary = '',
    this.reviewInsights = const <String>[],
    this.sourceLabel = '',
    this.voteScore = 0,
    this.upvotes = 0,
    this.downvotes = 0,
  });

  final int facultyId;
  final String initial;
  final String name;
  final String email;
  final List<String> courses;
  final FacultyRatingStats stats;
  final String reviewSummary;
  final List<String> reviewInsights;
  final String sourceLabel;
  final int voteScore;
  final int upvotes;
  final int downvotes;

  factory FacultySummary.fromJson(Map<String, dynamic> json) {
    return FacultySummary(
      facultyId: (json['facultyId'] as num?)?.toInt() ?? 0,
      initial: '${json['initial'] ?? ''}'.trim(),
      name: '${json['name'] ?? ''}'.trim(),
      email: '${json['email'] ?? ''}'.trim(),
      courses:
          (json['courses'] as List?)
              ?.map((v) => '$v'.trim())
              .where((v) => v.isNotEmpty)
              .toList() ??
          const <String>[],
      stats: FacultyRatingStats.fromJson(
        (json['stats'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{},
      ),
      reviewSummary: '${json['reviewSummary'] ?? ''}'.trim(),
      reviewInsights:
          (json['reviewInsights'] as List?)
              ?.map((v) => '$v'.trim())
              .where((v) => v.isNotEmpty)
              .toList() ??
          const <String>[],
      sourceLabel: '${json['sourceLabel'] ?? ''}'.trim(),
      voteScore:
          (json['voteScore'] as num?)?.toInt() ??
          (json['vote_score'] as num?)?.toInt() ??
          0,
      upvotes:
          (json['upvotes'] as num?)?.toInt() ??
          (json['upVotes'] as num?)?.toInt() ??
          0,
      downvotes:
          (json['downvotes'] as num?)?.toInt() ??
          (json['downVotes'] as num?)?.toInt() ??
          0,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'facultyId': facultyId,
      'initial': initial,
      'name': name,
      'email': email,
      'courses': courses,
      'stats': <String, dynamic>{
        'reviewsTotal': stats.reviewsTotal,
        'overall': stats.overall,
        'teaching': stats.teaching,
        'fairness': stats.fairness,
        'behavior': stats.behavior,
      },
      'reviewSummary': reviewSummary,
      'reviewInsights': reviewInsights,
      'sourceLabel': sourceLabel,
      'voteScore': voteScore,
      'upvotes': upvotes,
      'downvotes': downvotes,
    };
  }
}

class FacultyReviewItem {
  const FacultyReviewItem({
    required this.reviewId,
    required this.facultyInitial,
    required this.facultyName,
    required this.overall,
    required this.teaching,
    required this.fairness,
    required this.behavior,
    required this.comment,
    required this.isApproved,
    required this.canDelete,
    required this.canReport,
    this.createdAt,
    this.updatedAt,
  });

  final int reviewId;
  final String facultyInitial;
  final String facultyName;
  final int overall;
  final int teaching;
  final int fairness;
  final int behavior;
  final String comment;
  final bool isApproved;
  final bool? canDelete;
  final bool canReport;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory FacultyReviewItem.fromJson(Map<String, dynamic> json) {
    final ratings = (json['ratings'] as Map?)?.cast<String, dynamic>();
    return FacultyReviewItem(
      reviewId: (json['reviewId'] as num?)?.toInt() ?? 0,
      facultyInitial: '${json['facultyInitial'] ?? ''}'.trim(),
      facultyName: '${json['facultyName'] ?? ''}'.trim(),
      overall:
          (ratings?['overall'] as num?)?.toInt() ??
          (json['overall'] as num?)?.toInt() ??
          0,
      teaching:
          (ratings?['teaching'] as num?)?.toInt() ??
          (json['teaching'] as num?)?.toInt() ??
          0,
      fairness:
          (ratings?['fairness'] as num?)?.toInt() ??
          (json['fairness'] as num?)?.toInt() ??
          0,
      behavior:
          (ratings?['behavior'] as num?)?.toInt() ??
          (json['behavior'] as num?)?.toInt() ??
          0,
      comment: '${json['comment'] ?? ''}'.trim(),
      isApproved: json['isApproved'] == true || json['is_approved'] == true,
      canDelete: (json['canDelete'] as bool?) ?? (json['can_delete'] as bool?),
      canReport:
          (json['canReport'] as bool?) ?? (json['can_report'] as bool?) ?? true,
      createdAt: DateTime.tryParse(
        '${json['createdAt'] ?? json['created_at'] ?? ''}',
      ),
      updatedAt: DateTime.tryParse(
        '${json['updatedAt'] ?? json['updated_at'] ?? ''}',
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'reviewId': reviewId,
      'facultyInitial': facultyInitial,
      'facultyName': facultyName,
      'overall': overall,
      'teaching': teaching,
      'fairness': fairness,
      'behavior': behavior,
      'comment': comment,
      'isApproved': isApproved,
      'canDelete': canDelete,
      'canReport': canReport,
      'createdAt': createdAt?.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
    };
  }
}

class FacultyReviewFeed {
  const FacultyReviewFeed({
    required this.faculty,
    required this.reviews,
    required this.limit,
    required this.offset,
  });

  final FacultySummary faculty;
  final List<FacultyReviewItem> reviews;
  final int limit;
  final int offset;

  factory FacultyReviewFeed.fromJson(Map<String, dynamic> json) {
    final facultyJson =
        (json['faculty'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final items =
        (json['reviews'] as List?)
            ?.whereType<Map>()
            .map((e) => FacultyReviewItem.fromJson(e.cast<String, dynamic>()))
            .toList() ??
        const <FacultyReviewItem>[];
    return FacultyReviewFeed(
      faculty: FacultySummary.fromJson(facultyJson),
      reviews: items,
      limit: (json['limit'] as num?)?.toInt() ?? 20,
      offset: (json['offset'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'faculty': faculty.toJson(),
      'reviews': reviews.map((item) => item.toJson()).toList(),
      'limit': limit,
      'offset': offset,
    };
  }
}

class FacultyReviewUpsertInput {
  const FacultyReviewUpsertInput({
    required this.facultyInitial,
    required this.overall,
    required this.teaching,
    required this.fairness,
    required this.behavior,
    required this.comment,
  });

  final String facultyInitial;
  final int overall;
  final int teaching;
  final int fairness;
  final int behavior;
  final String comment;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'facultyInitial': facultyInitial,
      'overall': overall,
      'teaching': teaching,
      'fairness': fairness,
      'behavior': behavior,
      'comment': comment,
    };
  }
}

class FacultyReviewService {
  FacultyReviewService._internal();
  static final FacultyReviewService _instance =
      FacultyReviewService._internal();
  factory FacultyReviewService() => _instance;

  final ApiClient _client = ApiClient();
  final AppPreferencesStore _store = AppPreferencesStore();
  static final Map<String, FacultyReviewFeed> _feedCache =
      <String, FacultyReviewFeed>{};
  static final Map<String, FacultySummary> _summaryCache =
      <String, FacultySummary>{};
  static const String _feedCachePrefix = 'faculty_reviews_feed_v1';
  static const String _summaryCachePrefix = 'faculty_reviews_summary_v1';

  String get _base => ApiConfig.seatStatusProxyBase;

  Future<FacultyReviewFeed> getFacultyReviews(
    String facultyInitial, {
    int limit = 20,
    int offset = 0,
  }) async {
    final initial = facultyInitial.trim().toUpperCase();
    final cached = await _readCachedFeed(initial);
    if (cached != null) {
      return _sliceFeed(cached, limit: limit, offset: offset);
    }
    final apiBundle = await _fetchApiBundle(initial);
    final dbFeed = await _fetchDatabaseFeed(
      initial,
      limit: limit,
      offset: offset,
    );

    final summary =
        apiBundle?.summary ??
        dbFeed?.faculty ??
        FacultySummary(
          facultyId: 0,
          initial: initial,
          name: '',
          email: '',
          courses: const <String>[],
          stats: const FacultyRatingStats(
            reviewsTotal: 0,
            overall: 0,
            teaching: 0,
            fairness: 0,
            behavior: 0,
          ),
          reviewSummary: '',
          reviewInsights: const <String>[],
          sourceLabel: '',
          voteScore: 0,
          upvotes: 0,
          downvotes: 0,
        );
    final dbReviews = dbFeed?.reviews ?? const <FacultyReviewItem>[];
    final apiReviews = apiBundle?.reviews ?? const <FacultyReviewItem>[];
    final merged = <FacultyReviewItem>[...dbReviews, ...apiReviews];
    final seen = <String>{};
    final unique = merged.where((review) {
      final key = review.reviewId != 0
          ? 'id:${review.reviewId}'
          : '${review.facultyInitial}|${review.overall}|${review.teaching}|${review.fairness}|${review.behavior}|${review.comment.trim().toLowerCase()}';
      return seen.add(key);
    }).toList();
    final safeOffset = offset < 0 ? 0 : offset;
    final safeLimit = limit <= 0 ? unique.length : limit;
    final paged = unique.skip(safeOffset).take(safeLimit).toList();
    final feed = FacultyReviewFeed(
      faculty: summary,
      reviews: paged,
      limit: safeLimit,
      offset: safeOffset,
    );
    _feedCache[initial] = feed;
    _summaryCache[initial] = summary;
    unawaited(_writeCachedFeed(initial, feed));
    return feed;
  }

  Future<FacultySummary?> getFacultyByInitial(String facultyInitial) async {
    final initial = facultyInitial.trim().toUpperCase();
    if (initial.isEmpty) return null;
    final cachedSummary = _summaryCache[initial];
    if (cachedSummary != null) return cachedSummary;
    final cachedFeed = await _readCachedFeed(initial);
    if (cachedFeed != null) {
      return cachedFeed.faculty;
    }
    try {
      final response = await _client.publicGet(
        '$_base/data/facultyreviews',
      );
      final root = _decodeMap(response.body);
      final scoped = _scopedFacultyData(root, initial);
      if (scoped == null || scoped.isEmpty) return null;
      final summary = _summaryFromDataScoped(scoped, initial);
      _summaryCache[initial] = summary;
      return summary;
    } catch (_) {
      return null;
    }
  }

  Future<FacultyReviewFeed?> _readCachedFeed(String initial) async {
    final cached = _feedCache[initial];
    if (cached != null) return cached;
    final raw = await _store.getJsonMap('${_feedCachePrefix}_$initial');
    if (raw == null) return null;
    try {
      final feed = FacultyReviewFeed.fromJson(raw);
      _feedCache[initial] = feed;
      _summaryCache[initial] = feed.faculty;
      return feed;
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeCachedFeed(String initial, FacultyReviewFeed feed) async {
    try {
      await _store.setJson('${_feedCachePrefix}_$initial', feed.toJson());
      await _store.setJson(
        '${_summaryCachePrefix}_$initial',
        feed.faculty.toJson(),
      );
    } catch (_) {}
  }

  FacultyReviewFeed _sliceFeed(
    FacultyReviewFeed feed, {
    required int limit,
    required int offset,
  }) {
    final safeOffset = offset < 0 ? 0 : offset;
    final safeLimit = limit <= 0 ? feed.reviews.length : limit;
    return FacultyReviewFeed(
      faculty: feed.faculty,
      reviews: feed.reviews.skip(safeOffset).take(safeLimit).toList(),
      limit: safeLimit,
      offset: safeOffset,
    );
  }

  Future<FacultyReviewItem> upsertReview(FacultyReviewUpsertInput input) async {
    final response = await _client.authenticatedRequest(
      'POST',
      '$_base/v1/faculty-reviews',
      body: jsonEncode(input.toJson()),
      additionalHeaders: const <String, String>{
        'Content-Type': 'application/json',
      },
    );
    final map = _decodeMap(response.body);
    final item =
        (map['item'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    return FacultyReviewItem.fromJson(item);
  }

  Future<void> deleteReview(int reviewId) async {
    await _client.authenticatedRequest(
      'DELETE',
      '$_base/v1/faculty-reviews/$reviewId',
    );
  }

  Future<bool> reportReview(int reviewId, {required String reason}) async {
    final response = await _client.authenticatedRequest(
      'POST',
      '$_base/v1/faculty-reviews/$reviewId/report',
      body: jsonEncode(<String, dynamic>{'reason': reason}),
      additionalHeaders: const <String, String>{
        'Content-Type': 'application/json',
      },
    );
    final map = _decodeMap(response.body);
    return map['reported'] == true;
  }

  Map<String, dynamic> _decodeMap(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return decoded.cast<String, dynamic>();
    } catch (_) {}
    return const <String, dynamic>{};
  }

  Map<String, dynamic>? _scopedFacultyData(
    Map<String, dynamic> root,
    String initial,
  ) {
    return (root[initial] as Map?)?.cast<String, dynamic>() ??
        (root[initial.toLowerCase()] as Map?)?.cast<String, dynamic>() ??
        (root[initial.toUpperCase()] as Map?)?.cast<String, dynamic>();
  }

  FacultySummary _summaryFromDataScoped(
    Map<String, dynamic> scoped,
    String fallbackInitial,
  ) {
    final faculty =
        (scoped['faculty'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final score =
        (scoped['score_summary'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final reviewSummary = '${scoped['review_summary'] ?? ''}'.trim();
    final reviewInsights =
        (scoped['review_insights'] as List?)
            ?.map((v) => '$v'.trim())
            .where((v) => v.isNotEmpty)
            .toList() ??
        const <String>[];
    final reviewsTotal = (scoped['reviews_total'] as num?)?.toInt() ?? 0;
    final voteScore = (scoped['vote_score'] as num?)?.toInt() ?? 0;
    final explicitUpvotes =
        (scoped['upvotes'] as num?)?.toInt() ??
        (scoped['upVotes'] as num?)?.toInt() ??
        0;
    final explicitDownvotes =
        (scoped['downvotes'] as num?)?.toInt() ??
        (scoped['downVotes'] as num?)?.toInt() ??
        0;
    final derivedUpvotes = explicitUpvotes > 0
        ? explicitUpvotes
        : (voteScore > 0 ? voteScore : 0);
    final derivedDownvotes = explicitDownvotes > 0
        ? explicitDownvotes
        : (voteScore < 0 ? voteScore.abs() : 0);
    final teaching = (score['teaching'] as num?)?.toDouble() ?? 0;
    final marking = (score['marking'] as num?)?.toDouble() ?? 0;
    final behavior = (score['behavior'] as num?)?.toDouble() ?? 0;
    final pieces = <double>[
      teaching,
      marking,
      behavior,
    ].where((v) => v > 0).toList();
    final overall = pieces.isEmpty
        ? 0.0
        : pieces.reduce((a, b) => a + b) / pieces.length;
    return FacultySummary(
      facultyId: 0,
      initial: ('${faculty['initial'] ?? ''}'.trim().isNotEmpty
          ? '${faculty['initial']}'.trim()
          : fallbackInitial),
      name: '${faculty['faculty_name'] ?? faculty['name'] ?? ''}'.trim(),
      email: '${faculty['email'] ?? ''}'.trim(),
      courses:
          (faculty['courses'] as List?)
              ?.map((v) => '$v'.trim())
              .where((v) => v.isNotEmpty)
              .toList() ??
          const <String>[],
      stats: FacultyRatingStats(
        reviewsTotal: reviewsTotal,
        overall: overall,
        teaching: teaching,
        fairness: marking,
        behavior: behavior,
      ),
      reviewSummary: reviewSummary,
      reviewInsights: reviewInsights,
      sourceLabel: reviewsTotal == 0 ? 'Facebook posts/comments' : '',
      voteScore: voteScore,
      upvotes: derivedUpvotes,
      downvotes: derivedDownvotes,
    );
  }

  List<FacultyReviewItem> _reviewsFromDataScoped(
    Map<String, dynamic> scoped,
    String fallbackInitial,
  ) {
    final rows =
        (scoped['reviews'] as List?)
            ?.whereType<Map>()
            .map((e) => e.cast<String, dynamic>())
            .toList() ??
        const <Map<String, dynamic>>[];
    return rows.asMap().entries.map((entry) {
      final idx = entry.key;
      final row = entry.value;
      final initial = ('${row['facultyInitial'] ?? ''}'.trim().isNotEmpty
          ? '${row['facultyInitial']}'.trim()
          : fallbackInitial);
      final name = '${row['facultyName'] ?? ''}'.trim();
      final parsed = _parseRatingsText('${row['ratings'] ?? ''}');
      return FacultyReviewItem(
        reviewId: -1 * (idx + 1),
        facultyInitial: initial,
        facultyName: name,
        overall: parsed.overall,
        teaching: parsed.teaching,
        fairness: parsed.fairness,
        behavior: parsed.behavior,
        comment: '${row['comment'] ?? ''}'.trim(),
        isApproved: true,
        canDelete: false,
        canReport: false,
      );
    }).toList();
  }

  _ParsedRatings _parseRatingsText(String raw) {
    int scoreFor(List<String> labels) {
      for (final label in labels) {
        final reg = RegExp(
          '$label\\s*:\\s*Rated\\s*([0-9]+(?:\\.[0-9]+)?)',
          caseSensitive: false,
        );
        final match = reg.firstMatch(raw);
        if (match == null) continue;
        final value = double.tryParse(match.group(1) ?? '');
        if (value == null) continue;
        return value.round();
      }
      return 0;
    }

    final overall = scoreFor(const <String>['Overall']);
    final teaching = scoreFor(const <String>['Teaching']);
    final fairness = scoreFor(const <String>['Fairness', 'Marking']);
    final behavior = scoreFor(const <String>[
      'Behavior',
      'Behaviour',
      'Conduct',
    ]);
    final fallbackOverall = _averageFromNonZero(<int>[
      teaching,
      fairness,
      behavior,
    ]);
    return _ParsedRatings(
      overall: overall > 0 ? overall : fallbackOverall,
      teaching: teaching,
      fairness: fairness,
      behavior: behavior,
    );
  }

  Future<_ApiFacultyBundle?> _fetchApiBundle(String initial) async {
    try {
      final response = await _client.publicGet(
        '$_base/data/facultyreviews',
      );
      final root = _decodeMap(response.body);
      final scoped = _scopedFacultyData(root, initial);
      if (scoped == null || scoped.isEmpty) return null;
      return _ApiFacultyBundle(
        summary: _summaryFromDataScoped(scoped, initial),
        reviews: _reviewsFromDataScoped(scoped, initial),
      );
    } catch (_) {
      return null;
    }
  }

  Future<FacultyReviewFeed?> _fetchDatabaseFeed(
    String initial, {
    required int limit,
    required int offset,
  }) async {
    Future<FacultyReviewFeed?> request(String path) async {
      try {
        final response = await _client.authenticatedRequest('GET', path);
        final map = _decodeMap(response.body);
        return FacultyReviewFeed.fromJson(map);
      } catch (_) {
        return null;
      }
    }

    final byPath = await request(
      '$_base/v1/faculty-reviews/$initial?limit=$limit&offset=$offset',
    );
    if (byPath != null) return byPath;
    return request(
      '$_base/v1/faculty-reviews?facultyInitial=$initial&limit=$limit&offset=$offset',
    );
  }

  int _averageFromNonZero(List<int> values) {
    final filtered = values.where((v) => v > 0).toList();
    if (filtered.isEmpty) return 0;
    final sum = filtered.fold<int>(0, (a, b) => a + b);
    return (sum / filtered.length).round();
  }
}

class _ApiFacultyBundle {
  const _ApiFacultyBundle({required this.summary, required this.reviews});

  final FacultySummary summary;
  final List<FacultyReviewItem> reviews;
}

class _ParsedRatings {
  const _ParsedRatings({
    required this.overall,
    required this.teaching,
    required this.fairness,
    required this.behavior,
  });

  final int overall;
  final int teaching;
  final int fairness;
  final int behavior;
}
