import 'dart:convert';

import 'package:preconnect/tools/app_storage.dart';

class AppPreferencesStore {
  Future<String?> getString(String key) async {
    return AppStorage.instance.getString(key);
  }

  Future<void> setString(String key, String value) async {
    await AppStorage.instance.setString(key, value);
  }

  Future<bool?> getBool(String key) async {
    return AppStorage.instance.getBool(key);
  }

  Future<void> setBool(String key, bool value) async {
    await AppStorage.instance.setBool(key, value);
  }

  Future<int?> getInt(String key) async {
    return AppStorage.instance.getInt(key);
  }

  Future<void> setInt(String key, int value) async {
    await AppStorage.instance.setInt(key, value);
  }

  Future<List<String>?> getStringList(String key) async {
    return AppStorage.instance.getStringList(key);
  }

  Future<void> setStringList(String key, List<String> values) async {
    await AppStorage.instance.setStringList(key, values);
  }

  Future<void> setStringMap(Map<String, String> values) async {
    if (values.isEmpty) return;
    for (final entry in values.entries) {
      await AppStorage.instance.setString(entry.key, entry.value);
    }
  }

  Future<Map<String, String?>> getStringMap(Set<String> keys) async {
    final output = <String, String?>{};
    for (final key in keys) {
      output[key] = await AppStorage.instance.getString(key);
    }
    return output;
  }

  Future<void> setJson(String key, dynamic value) async {
    await AppStorage.instance.setString(key, jsonEncode(value));
  }

  Future<void> setJsonIfChanged(String key, dynamic value) async {
    final next = jsonEncode(value);
    final current = await getString(key);
    if (current == next) return;
    await setString(key, next);
  }

  Future<Map<String, dynamic>?> getJsonMap(String key) async {
    final raw = await getString(key);
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return decoded.cast<String, dynamic>();
    } catch (_) {
      return null;
    }
  }

  Future<List<dynamic>?> getJsonList(String key) async {
    final raw = await getString(key);
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is List ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> remove(String key) async {
    await AppStorage.instance.remove(key);
  }

  Future<void> clearAll() async {
    await AppStorage.instance.clear();
  }

  Future<void> clearAllExcept(Set<String> keepKeys) async {
    await AppStorage.instance.clearExcept(keepKeys);
  }
}

Future<String?> readStoredStringWithFallback({
  required String key,
  required bool fromFetch,
  required Future<String?> Function() onCacheMiss,
}) async {
  final stored = await AppPreferencesStore().getString(key);
  if (stored == null || stored.isEmpty) {
    if (fromFetch) return null;
    return onCacheMiss();
  }
  return stored;
}

Future<T?> readStoredJsonMapWithFallback<T>({
  required String key,
  required bool fromFetch,
  required T? Function(Map<String, dynamic> value) decoder,
  required Future<T?> Function() onCacheMiss,
}) async {
  final stored = await AppPreferencesStore().getJsonMap(key);
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
