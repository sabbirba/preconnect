import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class AppStorage {
  AppStorage._();

  static final AppStorage instance = AppStorage._();
  static SharedPreferences? _prefs;

  static Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
  }

  static Future<SharedPreferences> _getInstance() async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  Future<String?> getString(String key) async {
    final prefs = await _getInstance();
    final value = prefs.getString(key);
    return value;
  }

  Future<void> setString(String key, String value) async {
    final prefs = await _getInstance();
    await prefs.setString(key, value);
  }

  Future<bool?> getBool(String key) async {
    final raw = await getString(key);
    if (raw == null || raw.isEmpty) return null;
    return raw == 'true';
  }

  Future<void> setBool(String key, bool value) async {
    await setString(key, value ? 'true' : 'false');
  }

  Future<int?> getInt(String key) async {
    final raw = await getString(key);
    return raw == null ? null : int.tryParse(raw);
  }

  Future<void> setInt(String key, int value) async {
    await setString(key, value.toString());
  }

  Future<List<String>?> getStringList(String key) async {
    final raw = await getString(key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return null;
      return decoded.map((e) => '$e').toList();
    } catch (_) {
      return null;
    }
  }

  Future<void> setStringList(String key, List<String> values) async {
    await setString(key, jsonEncode(values));
  }

  Future<bool> containsKey(String key) async {
    final prefs = await _getInstance();
    return prefs.containsKey(key);
  }

  Future<void> remove(String key) async {
    final prefs = await _getInstance();
    await prefs.remove(key);
  }

  Future<void> clear() async {
    final prefs = await _getInstance();
    await prefs.clear();
  }

  Future<void> clearExcept(Set<String> keepKeys) async {
    final prefs = await _getInstance();
    final keys = prefs.getKeys();
    for (final key in keys) {
      if (keepKeys.contains(key)) continue;
      await prefs.remove(key);
    }
  }
}
