import 'dart:convert';

import 'package:preconnect/api/api_client.dart';
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/api/repository_cache.dart';
import 'package:preconnect/model/bracu_leaks.dart';

class BracuLeaksService {
  BracuLeaksService({ApiClient? client, RepositoryCache? cache})
    : _client = client ?? ApiClient(),
      _cache = cache ?? RepositoryCache.instance;

  static const String _collectionsCacheKey = 'bracu_leaks_collections_v1';
  static final Map<String, BracuLeaksDetail> _detailCache =
      <String, BracuLeaksDetail>{};
  static List<BracuLeaksCollection>? _collectionsCache;

  final ApiClient _client;
  final RepositoryCache _cache;

  Future<List<BracuLeaksCollection>> loadCollections({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _collectionsCache != null) {
      return _collectionsCache!;
    }
    try {
      final url = forceRefresh
          ? '${ApiConfig.bracuLeaksUrl}?refresh=${DateTime.now().millisecondsSinceEpoch}'
          : ApiConfig.bracuLeaksUrl;
      final response = await _client.publicGet(
        url,
        acceptedStatusCodes: const <int>{200},
        cacheDuration: const Duration(minutes: 10),
      );
      final collections = _parseCollections(response.body);
      _collectionsCache = collections;
      await _cache.writeString(_collectionsCacheKey, response.body);
      return collections;
    } catch (_) {
      final cached = await _cache.readString(_collectionsCacheKey);
      if (cached == null || cached.isEmpty) rethrow;
      final collections = _parseCollections(cached);
      _collectionsCache = collections;
      return collections;
    }
  }

  Future<BracuLeaksDetail> loadDetail(
    String code, {
    bool forceRefresh = false,
  }) async {
    final normalizedCode = code.trim();
    final cachedDetail = _detailCache[normalizedCode];
    if (!forceRefresh && cachedDetail != null) {
      return cachedDetail;
    }
    final cacheKey = 'bracu_leaks_detail_${normalizedCode.toLowerCase()}_v1';
    try {
      final collectionUrl = ApiConfig.bracuLeaksCollectionUrl(normalizedCode);
      final url = forceRefresh
          ? '$collectionUrl?refresh=${DateTime.now().millisecondsSinceEpoch}'
          : collectionUrl;
      final response = await _client.publicGet(
        url,
        acceptedStatusCodes: const <int>{200},
        cacheDuration: const Duration(minutes: 10),
      );
      final detail = _parseDetail(response.body);
      _detailCache[normalizedCode] = detail;
      await _cache.writeString(cacheKey, response.body);
      return detail;
    } catch (_) {
      final cached = await _cache.readString(cacheKey);
      if (cached == null || cached.isEmpty) rethrow;
      final detail = _parseDetail(cached);
      _detailCache[normalizedCode] = detail;
      return detail;
    }
  }

  List<BracuLeaksCollection> _parseCollections(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! List) throw const FormatException('Expected a list');
    return decoded
        .whereType<Map>()
        .map(
          (item) => BracuLeaksCollection.fromJson(item.cast<String, dynamic>()),
        )
        .where((item) => item.code.isNotEmpty)
        .toList(growable: false);
  }

  BracuLeaksDetail _parseDetail(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map) throw const FormatException('Expected an object');
    return BracuLeaksDetail.fromJson(decoded.cast<String, dynamic>());
  }
}
