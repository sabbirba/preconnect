import 'package:preconnect/api/preferences_store.dart';

class RepositoryCache {
  RepositoryCache._();

  static final RepositoryCache instance = RepositoryCache._();

  final AppPreferencesStore _store = AppPreferencesStore();

  Future<String?> readString(String key) {
    return _store.getString(key);
  }

  Future<int?> readInt(String key) {
    return _store.getInt(key);
  }

  Future<void> writeInt(String key, int value) {
    return _store.setInt(key, value);
  }

  Future<Map<String, String?>> readStringMap(Set<String> keys) {
    return _store.getStringMap(keys);
  }

  Future<void> writeString(String key, String value) {
    return _store.setString(key, value);
  }

  Future<void> writeStringMap(Map<String, String> values) {
    return _store.setStringMap(values);
  }

  Future<void> writeJson(String key, dynamic value) {
    return _store.setJson(key, value);
  }

  Future<void> writeJsonIfChanged(String key, dynamic value) {
    return _store.setJsonIfChanged(key, value);
  }

  Future<Map<String, dynamic>?> readJsonMap(String key) {
    return _store.getJsonMap(key);
  }

  Future<void> remove(String key) {
    return _store.remove(key);
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
