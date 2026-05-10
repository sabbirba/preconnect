import 'package:preconnect/api/app_preferences_store.dart';

class OfflineCacheHelper {
  OfflineCacheHelper._();

  static final OfflineCacheHelper instance = OfflineCacheHelper._();
  final AppPreferencesStore _store = AppPreferencesStore();

  Future<T> loadJson<T>({
    required String cacheKey,
    required Duration ttl,
    required bool forceRefresh,
    required Future<T> Function() fetcher,
    required T? Function(dynamic cachedData) decoder,
  }) async {
    if (!forceRefresh) {
      final cached = await _read(cacheKey: cacheKey, ttl: ttl);
      final decoded = decoder(cached);
      if (decoded != null) return decoded;
    }

    try {
      final fresh = await fetcher();
      return fresh;
    } catch (_) {
      final cached = await _read(cacheKey: cacheKey, ttl: null);
      final decoded = decoder(cached);
      if (decoded != null) return decoded;
      rethrow;
    }
  }

  Future<dynamic> _read({
    required String cacheKey,
    required Duration? ttl,
  }) async {
    final stored = await _store.getCachedJsonMap(cacheKey);
    final ts = stored?['ts'];
    final data = stored?['data'];
    if (data == null) return null;
    if (ttl == null) return data;
    if (ts is! int) return null;
    final age = DateTime.now().difference(
      DateTime.fromMillisecondsSinceEpoch(ts),
    );
    if (age > ttl) return null;
    return data;
  }

  Future<void> saveJson(String cacheKey, dynamic data) async {
    await _store.setCachedJson(
      cacheKey,
      data,
      timestampMs: DateTime.now().millisecondsSinceEpoch,
    );
  }
}
