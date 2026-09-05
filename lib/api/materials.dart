import 'dart:convert';

import 'package:preconnect/api/api_client.dart';
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/api/repository_cache.dart';
import 'package:preconnect/model/materials.dart';

class MaterialsService {
  MaterialsService({ApiClient? client, RepositoryCache? cache})
    : _client = client ?? ApiClient(),
      _cache = cache ?? RepositoryCache.instance;

  static const String _sourcesCacheKey = 'materials_sources_v1';
  static final Map<String, MaterialDetail> _detailCache =
      <String, MaterialDetail>{};
  static final Map<String, List<MaterialCollection>> _sourceCollectionsCache =
      <String, List<MaterialCollection>>{};
  static MaterialSources? _sourcesCache;

  final ApiClient _client;
  final RepositoryCache _cache;

  Future<MaterialSources> loadSources({bool forceRefresh = false}) async {
    if (!forceRefresh && _sourcesCache != null) {
      return _sourcesCache!;
    }
    try {
      final url = forceRefresh
          ? '${ApiConfig.materialsUrl}?refresh=${DateTime.now().millisecondsSinceEpoch}'
          : ApiConfig.materialsUrl;
      final response = await _client.publicGet(
        url,
        acceptedStatusCodes: const <int>{200},
        cacheDuration: const Duration(minutes: 10),
      );
      final sources = _parseSources(response.body);
      _sourcesCache = sources;
      await _cache.writeString(_sourcesCacheKey, response.body);
      return sources;
    } catch (_) {
      final cached = await _cache.readString(_sourcesCacheKey);
      if (cached == null || cached.isEmpty) rethrow;
      final sources = _parseSources(cached);
      _sourcesCache = sources;
      return sources;
    }
  }

  Future<List<MaterialCollection>> loadCollections(
    String source, {
    bool forceRefresh = false,
  }) async {
    final key = source.trim();
    final cached = _sourceCollectionsCache[key];
    if (!forceRefresh && cached != null) {
      return cached;
    }
    final cacheKey = 'materials_collections_${key.toLowerCase()}_v1';
    try {
      final baseUrl = ApiConfig.materialsSourceUrl(key);
      final url = forceRefresh
          ? '$baseUrl?refresh=${DateTime.now().millisecondsSinceEpoch}'
          : baseUrl;
      final response = await _client.publicGet(
        url,
        acceptedStatusCodes: const <int>{200},
        cacheDuration: const Duration(minutes: 10),
      );
      final collections = _parseCollections(response.body);
      _sourceCollectionsCache[key] = collections;
      await _cache.writeString(cacheKey, response.body);
      return collections;
    } catch (_) {
      final cachedString = await _cache.readString(cacheKey);
      if (cachedString == null || cachedString.isEmpty) rethrow;
      final collections = _parseCollections(cachedString);
      _sourceCollectionsCache[key] = collections;
      return collections;
    }
  }

  Future<MaterialDetail> loadDetail(
    String code, {
    required String source,
    bool forceRefresh = false,
  }) async {
    final normalizedCode = code.trim();
    final normalizedSource = source.trim();
    final cacheKey =
        'materials_detail_${normalizedSource.toLowerCase()}_${normalizedCode.toLowerCase()}_v1';
    final detailKey = '$normalizedSource/$normalizedCode';
    final cachedDetail = _detailCache[detailKey];
    if (!forceRefresh && cachedDetail != null) {
      return cachedDetail;
    }
    try {
      final baseUrl = ApiConfig.materialsDetailUrl(
        normalizedSource,
        normalizedCode,
      );
      final url = forceRefresh
          ? '$baseUrl?refresh=${DateTime.now().millisecondsSinceEpoch}'
          : baseUrl;
      final response = await _client.publicGet(
        url,
        acceptedStatusCodes: const <int>{200},
        cacheDuration: const Duration(minutes: 10),
      );
      final detail = _parseDetail(response.body);
      _detailCache[detailKey] = detail;
      await _cache.writeString(cacheKey, response.body);
      return detail;
    } catch (_) {
      final cached = await _cache.readString(cacheKey);
      if (cached == null || cached.isEmpty) rethrow;
      final detail = _parseDetail(cached);
      _detailCache[detailKey] = detail;
      return detail;
    }
  }

  MaterialSources _parseSources(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map) throw const FormatException('Expected an object');
    return MaterialSources.fromJson(decoded.cast<String, dynamic>());
  }

  List<MaterialCollection> _parseCollections(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! List) throw const FormatException('Expected a list');
    return decoded
        .whereType<Map>()
        .map(
          (item) => MaterialCollection.fromJson(item.cast<String, dynamic>()),
        )
        .where((item) => item.code.isNotEmpty)
        .toList(growable: false);
  }

  MaterialDetail _parseDetail(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map) throw const FormatException('Expected an object');
    return MaterialDetail.fromJson(decoded.cast<String, dynamic>());
  }
}
