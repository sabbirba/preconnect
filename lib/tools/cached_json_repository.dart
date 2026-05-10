import 'package:preconnect/tools/offline_cache_helper.dart';

class CachedJsonRepository {
  CachedJsonRepository({
    required this.cacheKey,
    required this.ttl,
  });

  final String cacheKey;
  final Duration ttl;

  Future<T> load<T>({
    required bool forceRefresh,
    required Future<T> Function() fetcher,
    required T? Function(dynamic cachedData) decoder,
  }) {
    return OfflineCacheHelper.instance.loadJson<T>(
      cacheKey: cacheKey,
      ttl: ttl,
      forceRefresh: forceRefresh,
      fetcher: fetcher,
      decoder: decoder,
    );
  }

  Future<void> save(dynamic data) {
    return OfflineCacheHelper.instance.saveJson(cacheKey, data);
  }
}

