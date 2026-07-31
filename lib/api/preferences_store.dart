import 'dart:convert';

import 'package:preconnect/tools/app_storage.dart';

class AppPreferencesStore {
  Future<String?> getString(String key) async {
    return AppStorage.instance.getString(key);
  }

  Future<void> setString(String key, String value) async {
    await AppStorage.instance.setString(key, value);
  }

  Future<int?> getInt(String key) async {
    return AppStorage.instance.getInt(key);
  }

  Future<void> setStringMap(Map<String, String> values) async {
    if (values.isEmpty) return;
    await Future.wait(
      values.entries.map(
        (entry) => AppStorage.instance.setString(entry.key, entry.value),
      ),
    );
  }

  Future<Map<String, String?>> getStringMap(Set<String> keys) async {
    final values = await Future.wait(
      keys.map((key) async => MapEntry(key, await getString(key))),
    );
    return Map<String, String?>.fromEntries(values);
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

  Future<void> remove(String key) async {
    await AppStorage.instance.remove(key);
  }
}
