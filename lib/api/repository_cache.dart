import 'package:http/http.dart' as http;
import 'package:preconnect/api/api_client.dart';
import 'package:preconnect/api/app_preferences_store.dart';

class RepositoryCache {
  RepositoryCache._();

  static final RepositoryCache instance = RepositoryCache._();

  final ApiClient _client = ApiClient();
  final AppPreferencesStore _store = AppPreferencesStore();

  Future<T?> fetchWithStoredEtag<T>({
    required String url,
    required bool fromGet,
    required String etagKey,
    required Future<void> Function(http.Response response) cacheResponse,
    required Future<T?> Function({required bool fromFetch}) readCache,
    Duration cacheDuration = const Duration(seconds: 2),
  }) async {
    return _client.fetchWithFallback<T>(
      url: url,
      fromGet: fromGet,
      cacheResponse: cacheResponse,
      readCache: readCache,
      cacheDuration: cacheDuration,
    );
  }

  Future<String?> readString(String key) async {
    return _store.getString(key);
  }

  Future<bool?> readBool(String key) async {
    return _store.getBool(key);
  }

  Future<int?> readInt(String key) async {
    return _store.getInt(key);
  }

  Future<List<String>?> readStringList(String key) async {
    return _store.getStringList(key);
  }

  Future<Map<String, String?>> readStringMap(Set<String> keys) async {
    return _store.getStringMap(keys);
  }

  Future<void> writeString(String key, String value) async {
    await _store.setString(key, value);
  }

  Future<void> writeBool(String key, bool value) async {
    await _store.setBool(key, value);
  }

  Future<void> writeInt(String key, int value) async {
    await _store.setInt(key, value);
  }

  Future<void> writeStringList(String key, List<String> values) async {
    await _store.setStringList(key, values);
  }

  Future<void> writeStringMap(Map<String, String> values) async {
    await _store.setStringMap(values);
  }

  Future<void> writeJson(String key, dynamic value) async {
    await _store.setJson(key, value);
  }

  Future<void> writeJsonIfChanged(String key, dynamic value) async {
    await _store.setJsonIfChanged(key, value);
  }

  Future<Map<String, dynamic>?> readJsonMap(String key) async {
    return _store.getJsonMap(key);
  }

  Future<void> remove(String key) async {
    await _store.remove(key);
  }

  Future<T?> readStringWithFallback<T>({
    required String key,
    required bool fromFetch,
    required Future<T?> Function() onCacheMiss,
    required T? Function(String value) decoder,
  }) async {
    final stored = await readString(key);
    if (stored == null || stored.isEmpty) {
      if (fromFetch) return null;
      return onCacheMiss();
    }
    try {
      return decoder(stored);
    } catch (_) {
      if (fromFetch) return null;
      return onCacheMiss();
    }
  }

  Future<T?> readStringMapWithFallback<T>({
    required Set<String> keys,
    required bool fromFetch,
    required Future<T?> Function() onCacheMiss,
    required T? Function(Map<String, String?> value) decoder,
  }) async {
    final stored = await readStringMap(keys);
    final hasValues = stored.values.any(
      (value) => value != null && value.isNotEmpty,
    );
    if (!hasValues) {
      if (fromFetch) return null;
      return onCacheMiss();
    }
    try {
      return decoder(stored);
    } catch (_) {
      if (fromFetch) return null;
      return onCacheMiss();
    }
  }

  Future<T?> readJsonMapWithFallback<T>({
    required String key,
    required bool fromFetch,
    required T? Function(Map<String, dynamic> value) decoder,
    required Future<T?> Function() onCacheMiss,
  }) async {
    final stored = await readJsonMap(key);
    if (stored == null) {
      if (fromFetch) return null;
      return onCacheMiss();
    }
    try {
      return decoder(stored);
    } catch (_) {
      if (fromFetch) return null;
      return onCacheMiss();
    }
  }
}
