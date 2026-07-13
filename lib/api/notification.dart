import 'dart:convert';

import 'package:intl/intl.dart';
import 'package:preconnect/api/api_client.dart';
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/api/repository_cache.dart';
import 'package:preconnect/tools/url_utils.dart';

class RecentConnectNotification {
  const RecentConnectNotification({
    required this.id,
    required this.title,
    required this.module,
    required this.link,
    required this.createdOn,
    required this.expireAt,
    required this.seen,
  });

  final int id;
  final String title;
  final String module;
  final String? link;
  final DateTime? createdOn;
  final DateTime? expireAt;
  final bool seen;

  factory RecentConnectNotification.fromJson(Map<String, dynamic> json) {
    return RecentConnectNotification(
      id: (json['id'] as num?)?.toInt() ?? 0,
      title: (json['title'] as String? ?? '').trim(),
      module: (json['module'] as String? ?? '').trim(),
      link: (json['link'] as String?)?.trim(),
      createdOn: DateTime.tryParse((json['createdOn'] as String? ?? '').trim()),
      expireAt: DateTime.tryParse((json['expireAt'] as String? ?? '').trim()),
      seen: json['seen'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'title': title,
      'module': module,
      'link': link,
      'createdOn': createdOn?.toIso8601String(),
      'expireAt': expireAt?.toIso8601String(),
      'seen': seen,
    };
  }
}

class ScraperDataService {
  ScraperDataService._internal();
  static final ScraperDataService _instance = ScraperDataService._internal();
  factory ScraperDataService() => _instance;

  final ApiClient _client = ApiClient();
  final RepositoryCache _repo = RepositoryCache.instance;
  static const Duration _requestCacheTtl = Duration(seconds: 30);

  Future<List<Map<String, dynamic>>> fetchList({
    required String path,
    required String cacheKey,
    required Duration ttl,
    bool forceRefresh = false,
  }) async {
    final data = await _fetchJson(
      path: path,
      cacheKey: cacheKey,
      ttl: ttl,
      forceRefresh: forceRefresh,
    );
    if (data is! List) return const <Map<String, dynamic>>[];
    return data
        .whereType<Map>()
        .map((item) => item.cast<String, dynamic>())
        .toList(growable: false);
  }

  Future<Map<String, dynamic>?> fetchMap({
    required String path,
    required String cacheKey,
    required Duration ttl,
    bool forceRefresh = false,
  }) async {
    final data = await _fetchJson(
      path: path,
      cacheKey: cacheKey,
      ttl: ttl,
      forceRefresh: forceRefresh,
    );
    if (data is! Map) return null;
    return data.cast<String, dynamic>();
  }

  Future<dynamic> _fetchJson({
    required String path,
    required String cacheKey,
    required Duration ttl,
    required bool forceRefresh,
  }) async {
    if (!forceRefresh) {
      final cached = await _repo.readJsonMap(cacheKey);
      final ts = cached?['ts'];
      final data = cached?['data'];
      if (ts is int && data != null) {
        final age = DateTime.now().difference(
          DateTime.fromMillisecondsSinceEpoch(ts),
        );
        if (age <= ttl) return data;
      }
    }

    final url = path.startsWith('http')
        ? path
        : '${ApiConfig.publicJsonBase}${path.startsWith('/') ? path : '/$path'}';
    try {
      final response = await _client.publicGet(
        url,
        cacheDuration: _requestCacheTtl,
      );
      final decoded = jsonDecode(response.body);
      await _repo.writeJson(cacheKey, <String, dynamic>{
        'ts': DateTime.now().millisecondsSinceEpoch,
        'data': decoded,
      });
      return decoded;
    } catch (_) {
      final cached = await _repo.readJsonMap(cacheKey);
      return cached?['data'];
    }
  }
}

class NotificationsFeed {
  const NotificationsFeed({required this.newCount, required this.items});

  final int newCount;
  final List<RecentConnectNotification> items;

  factory NotificationsFeed.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    final items = rawItems is List
        ? rawItems
              .whereType<Map>()
              .map(
                (item) => RecentConnectNotification.fromJson(
                  Map<String, dynamic>.from(item),
                ),
              )
              .toList()
        : const <RecentConnectNotification>[];
    return NotificationsFeed(
      newCount: (json['new'] as num?)?.toInt() ?? 0,
      items: items,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'new': newCount,
      'items': items.map((item) => item.toJson()).toList(),
    };
  }

  NotificationsFeed copyWith({
    int? newCount,
    List<RecentConnectNotification>? items,
  }) {
    return NotificationsFeed(
      newCount: newCount ?? this.newCount,
      items: items ?? this.items,
    );
  }
}

class ConnectNotificationDetail {
  const ConnectNotificationDetail({
    required this.id,
    required this.title,
    required this.module,
    required this.link,
    required this.expireAt,
    required this.createdOn,
    required this.details,
  });

  final int id;
  final String title;
  final String module;
  final String? link;
  final DateTime? expireAt;
  final DateTime? createdOn;
  final String details;

  factory ConnectNotificationDetail.fromJson(Map<String, dynamic> json) {
    return ConnectNotificationDetail(
      id: (json['id'] as num?)?.toInt() ?? 0,
      title: (json['title'] as String? ?? '').trim(),
      module: (json['module'] as String? ?? '').trim(),
      link: (json['link'] as String?)?.trim(),
      expireAt: DateTime.tryParse((json['expireAt'] as String? ?? '').trim()),
      createdOn: DateTime.tryParse((json['createdOn'] as String? ?? '').trim()),
      details: (json['details'] as String? ?? '').trim(),
    );
  }
}

class ScraperContentItem {
  const ScraperContentItem({
    required this.id,
    required this.source,
    required this.title,
    required this.message,
    required this.url,
    required this.publishedAt,
    this.imageUrl,
    this.imageUrls = const <String>[],
  });

  final String id;
  final String source;
  final String title;
  final String message;
  final String url;
  final DateTime? publishedAt;
  final String? imageUrl;
  final List<String> imageUrls;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'source': source,
      'title': title,
      'message': message,
      'url': url,
      'publishedAt': publishedAt?.toIso8601String(),
      'imageUrl': imageUrl,
      'imageUrls': imageUrls,
    };
  }

  factory ScraperContentItem.fromJson(Map<String, dynamic> json) {
    final rawImageUrls = json['imageUrls'];
    final imageUrls = rawImageUrls is List
        ? rawImageUrls.map((e) => '$e').toList(growable: false)
        : const <String>[];
    return ScraperContentItem(
      id: (json['id'] as String? ?? '').trim(),
      source: (json['source'] as String? ?? '').trim(),
      title: (json['title'] as String? ?? '').trim(),
      message: (json['message'] as String? ?? '').trim(),
      url: (json['url'] as String? ?? '').trim(),
      publishedAt: DateTime.tryParse(
        (json['publishedAt'] as String? ?? '').trim(),
      ),
      imageUrl: (json['imageUrl'] as String?)?.trim(),
      imageUrls: imageUrls,
    );
  }
}

class NotificationService {
  NotificationService._internal();
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;

  final ApiClient _client = ApiClient();
  final ScraperDataService _scraper = ScraperDataService();
  final RepositoryCache _repo = RepositoryCache.instance;

  static const String _recentFeedKey = 'RecentNotificationsFeed';
  static const String _scraperFeedCacheKey = 'scraper_notifications_feed_v1';
  static const String _scraperSeenIdsCacheKey = 'scraper_notifications_seen_v1';

  Future<List<ScraperContentItem>> getScraperContentFeed({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh) {
      final cached = await _readCachedScraperFeed();
      if (cached != null) return cached;
    }

    final results = await Future.wait<List<ScraperContentItem>>(
      <Future<List<ScraperContentItem>>>[
        _fetchScraperItems(
          path: ApiConfig.announcementFeedUrl,
          source: 'Announcement',
          cacheKey: 'scraper_announcements_v1',
          forceRefresh: forceRefresh,
        ),
        _fetchScraperItems(
          path: ApiConfig.newsFeedUrl,
          source: 'News',
          cacheKey: 'scraper_news_v1',
          forceRefresh: forceRefresh,
        ),
      ],
    );
    final merged = <ScraperContentItem>[...results[0], ...results[1]];
    merged.sort((a, b) {
      final aTime = a.publishedAt;
      final bTime = b.publishedAt;
      if (aTime == null && bTime == null) return 0;
      if (aTime == null) return 1;
      if (bTime == null) return -1;
      return bTime.compareTo(aTime);
    });
    await _writeCachedScraperFeed(merged);
    return merged;
  }

  Future<Set<String>> getSeenScraperNotificationIds() async {
    final cached = await _repo.readJsonMap(_scraperSeenIdsCacheKey);
    final raw = cached?['ids'];
    if (raw is! List) return <String>{};
    return raw
        .map((value) => '$value'.trim())
        .where((value) => value.isNotEmpty)
        .toSet();
  }

  Future<void> markScraperNotificationSeen(String id) async {
    final cleaned = id.trim();
    if (cleaned.isEmpty) return;
    final seen = await getSeenScraperNotificationIds();
    if (seen.contains(cleaned)) return;
    seen.add(cleaned);
    await _writeSeenScraperNotificationIds(seen);
  }

  Future<void> markAllScraperNotificationsSeen(Iterable<String> ids) async {
    final normalized = ids
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
    if (normalized.isEmpty) return;
    final seen = await getSeenScraperNotificationIds();
    seen.addAll(normalized);
    await _writeSeenScraperNotificationIds(seen);
  }

  Future<int> getTotalUnreadCount({bool forceRefresh = false}) async {
    final connect = forceRefresh
        ? await fetchRecentNotifications()
        : await getRecentNotifications();
    final scraper = await getScraperContentFeed(forceRefresh: forceRefresh);
    final seenScraperIds = await getSeenScraperNotificationIds();
    final scraperUnread = scraper
        .where((item) => !seenScraperIds.contains(item.id))
        .length;
    return (connect?.newCount ?? 0) + scraperUnread;
  }

  Future<NotificationsFeed?> fetchRecentNotifications({
    bool fromGet = false,
  }) async {
    final url =
        '${ApiConfig.connectApiBase}${ApiConfig.recentNotificationsPath}';
    try {
      final response = await _client.authenticatedGet(
        url,
        cacheDuration: const Duration(seconds: 10),
      );
      if (response.statusCode == 200) {
        await _repo.writeString(_recentFeedKey, response.body);
      }
    } catch (_) {}

    if (fromGet) return null;
    return getRecentNotifications(fromFetch: true);
  }

  Future<NotificationsFeed?> getRecentNotifications({
    bool fromFetch = false,
  }) async {
    final cached = await _readCachedFeed();
    if (cached != null || fromFetch) return cached;
    return fetchRecentNotifications(fromGet: true);
  }

  Future<ConnectNotificationDetail> fetchNotificationDetail(int id) async {
    final response = await _client.authenticatedGet(
      '${ApiConfig.connectApiBase}${ApiConfig.notificationViewPath(id)}',
      cacheDuration: const Duration(seconds: 10),
    );
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid notification detail response');
    }
    return ConnectNotificationDetail.fromJson(decoded);
  }

  Future<NotificationsFeed?> markAllSeen() async {
    final cached = await _readCachedFeed();
    if (cached == null) return null;
    final updated = cached.copyWith(
      newCount: 0,
      items: cached.items
          .map(
            (item) => item.seen
                ? item
                : RecentConnectNotification(
                    id: item.id,
                    title: item.title,
                    module: item.module,
                    link: item.link,
                    createdOn: item.createdOn,
                    expireAt: item.expireAt,
                    seen: true,
                  ),
          )
          .toList(),
    );
    await _repo.writeJson(_recentFeedKey, _feedToJson(updated));
    return updated;
  }

  Future<NotificationsFeed?> _readCachedFeed() async {
    return _repo.readJsonMapWithFallback<NotificationsFeed>(
      key: _recentFeedKey,
      fromFetch: true,
      decoder: NotificationsFeed.fromJson,
      onCacheMiss: () async => null,
    );
  }

  Future<List<ScraperContentItem>> _fetchScraperItems({
    required String path,
    required String source,
    required String cacheKey,
    required bool forceRefresh,
  }) async {
    final rows = await _scraper.fetchList(
      path: path,
      cacheKey: cacheKey,
      ttl: const Duration(hours: 3),
      forceRefresh: forceRefresh,
    );
    return rows
        .map((row) {
          final title = '${row['title'] ?? ''}'.trim();
          final message = '${row['message'] ?? ''}'.trim();
          final url = '${row['url'] ?? ''}'.trim();

          final imageUrls = _extractAndNormalizeImageUrls(row, baseUrl: url);

          final publishedRaw = '${row['published_date'] ?? ''}'.trim();
          if (title.isEmpty && message.isEmpty) return null;
          return ScraperContentItem(
            id: _scraperContentId(
              source: source,
              title: title,
              url: url,
              publishedAt: _parseScraperPublishedDate(publishedRaw),
            ),
            source: source,
            title: title,
            message: message,
            url: url,
            publishedAt: _parseScraperPublishedDate(publishedRaw),
            imageUrl: imageUrls.isEmpty ? null : imageUrls.first,
            imageUrls: imageUrls,
          );
        })
        .whereType<ScraperContentItem>()
        .toList(growable: false);
  }

  Future<List<ScraperContentItem>?> _readCachedScraperFeed() async {
    final cached = await _repo.readJsonMap(_scraperFeedCacheKey);
    if (cached == null) return null;
    final ts = cached['ts'];
    if (ts is int) {
      final age = DateTime.now().difference(
        DateTime.fromMillisecondsSinceEpoch(ts),
      );
      if (age > const Duration(hours: 3)) return null;
    }
    final rawItems = cached['items'];
    if (rawItems is! List) return null;
    return rawItems
        .whereType<Map>()
        .map((item) => item.cast<String, dynamic>())
        .map((item) {
          final baseUrl = (item['url'] ?? '').toString().trim();
          final cachedImageUrls = item['imageUrls'];
          final cachedImageUrl = item['imageUrl'];

          final imageUrlsToNormalize = <String>[];
          if (cachedImageUrls is List) {
            for (final url in cachedImageUrls) {
              final urlStr = '$url'.trim();
              if (urlStr.isNotEmpty) imageUrlsToNormalize.add(urlStr);
            }
          }
          if (cachedImageUrl is String) {
            final urlStr = cachedImageUrl.trim();
            if (urlStr.isNotEmpty && !imageUrlsToNormalize.contains(urlStr)) {
              imageUrlsToNormalize.add(urlStr);
            }
          }

          final normalizedImageUrls = imageUrlsToNormalize.isEmpty
              ? <String>[]
              : _normalizeScraperImageUrls(
                  imageUrlsToNormalize.join('|'),
                  baseUrl: baseUrl,
                );

          return ScraperContentItem(
            id: (item['id'] ?? '').toString().trim().isEmpty
                ? _scraperContentId(
                    source: (item['source'] ?? '').toString().trim(),
                    title: (item['title'] ?? '').toString().trim(),
                    url: baseUrl,
                    publishedAt: DateTime.tryParse(
                      (item['publishedAt'] ?? '').toString().trim(),
                    ),
                  )
                : (item['id'] ?? '').toString().trim(),
            source: (item['source'] ?? '').toString().trim(),
            title: (item['title'] ?? '').toString().trim(),
            message: (item['message'] ?? '').toString().trim(),
            url: baseUrl,
            publishedAt: DateTime.tryParse(
              (item['publishedAt'] ?? '').toString().trim(),
            ),
            imageUrl: normalizedImageUrls.isEmpty
                ? null
                : normalizedImageUrls.first,
            imageUrls: normalizedImageUrls,
          );
        })
        .toList(growable: false);
  }

  Future<void> _writeCachedScraperFeed(List<ScraperContentItem> items) async {
    await _repo.writeJson(_scraperFeedCacheKey, <String, dynamic>{
      'ts': DateTime.now().millisecondsSinceEpoch,
      'items': items
          .map(
            (item) => <String, dynamic>{
              'source': item.source,
              'title': item.title,
              'message': item.message,
              'url': item.url,
              'publishedAt': item.publishedAt?.toIso8601String() ?? '',
              'imageUrl': item.imageUrl ?? '',
              'imageUrls': item.imageUrls,
              'id': item.id,
            },
          )
          .toList(),
    });
  }

  Future<void> _writeSeenScraperNotificationIds(Set<String> ids) async {
    await _repo.writeJson(_scraperSeenIdsCacheKey, <String, dynamic>{
      'ids': ids.toList()..sort(),
    });
  }

  DateTime? _parseScraperPublishedDate(String raw) {
    if (raw.trim().isEmpty) return null;
    var normalized = raw
        .replaceAll('\n', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    normalized = normalized.replaceAllMapped(
      RegExp(r'\b(\d{1,2})(st|nd|rd|th)\b', caseSensitive: false),
      (m) => m.group(1) ?? '',
    );

    final formats = <String>[
      'EEEE, MMMM d, yyyy - HH:mm',
      'EEEE, MMMM d, yyyy - H:mm',
      'MMMM d, yyyy - HH:mm',
      'MMMM d, yyyy - H:mm',
      'MMMM d, yyyy',
      'MMM d, yyyy',
    ];
    for (final pattern in formats) {
      try {
        return DateFormat(pattern).parseLoose(normalized);
      } catch (_) {}
    }
    return DateTime.tryParse(normalized);
  }

  List<String> _extractAndNormalizeImageUrls(
    Map<String, dynamic> row, {
    required String baseUrl,
  }) {
    final candidates = <String>[];
    final value = row['image_url'];
    if (value != null) {
      if (value is String) {
        final trimmed = value.trim();
        if (trimmed.isNotEmpty) {
          candidates.add(trimmed);
        }
      } else if (value is List) {
        for (final item in value) {
          final itemStr = '$item'.trim();
          if (itemStr.isNotEmpty) {
            candidates.add(itemStr);
          }
        }
      }
    }

    return _normalizeScraperImageUrls(candidates.join('|'), baseUrl: baseUrl);
  }

  List<String> _normalizeScraperImageUrls(String raw, {String? baseUrl}) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return const <String>[];

    final candidates = <String>[];

    if (trimmed.contains('|')) {
      for (final part in trimmed.split('|')) {
        final p = part.trim();
        if (p.isNotEmpty) candidates.add(p);
      }
    } else if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is List) {
          for (final item in decoded) {
            final value = '$item'.trim();
            if (value.isNotEmpty) candidates.add(value);
          }
        }
      } catch (_) {}
    } else if (trimmed.contains(',')) {
      for (final part in trimmed.split(',')) {
        final p = part.trim();
        if (p.isNotEmpty) candidates.add(p);
      }
    } else {
      candidates.add(trimmed);
    }

    final output = <String, String>{};
    for (var rawUrl in candidates) {
      final normalized = normalizeImageUrl(rawUrl, baseUrl: baseUrl);
      if (normalized != null && normalized.isNotEmpty) {
        output[normalized] = normalized;
      }
    }

    return output.values.toList(growable: false);
  }

  String _scraperContentId({
    required String source,
    required String title,
    required String url,
    required DateTime? publishedAt,
  }) {
    final token =
        '${source.trim().toLowerCase()}|${title.trim().toLowerCase()}|${url.trim().toLowerCase()}|${publishedAt?.toIso8601String() ?? ''}';
    var hash = 2166136261;
    for (final codeUnit in token.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 16777619) & 0xFFFFFFFF;
    }
    return 'scr_${hash.toUnsigned(32).toRadixString(16)}';
  }

  Map<String, dynamic> _feedToJson(NotificationsFeed feed) {
    return <String, dynamic>{
      'new': feed.newCount,
      'items': feed.items
          .map(
            (item) => <String, dynamic>{
              'id': item.id,
              'title': item.title,
              'module': item.module,
              'link': item.link,
              'createdOn': item.createdOn?.toIso8601String(),
              'expireAt': item.expireAt?.toIso8601String(),
              'seen': item.seen,
            },
          )
          .toList(),
    };
  }
}
