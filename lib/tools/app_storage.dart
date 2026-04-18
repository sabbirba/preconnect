import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppStorage {
  AppStorage._();

  static final AppStorage instance = AppStorage._();
  static SharedPreferences? _prefs;

  /// Initialize SharedPreferences instance (call once at app startup)
  static Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
    debugPrint('[APP_STORAGE] Initialized SharedPreferences instance');

    // NOTE: We DO NOT clear FlutterSecureStorage on startup because we use it as a
    // critical backup storage for authentication tokens. Clearing it would destroy
    // our token backup mechanism and force users to re-login.
    // The original code that did deleteAll() every startup was a mistake.
  }

  /// Get the SharedPreferences instance, initializing if needed
  static Future<SharedPreferences> _getInstance() async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  Future<String?> getString(String key) async {
    final prefs = await _getInstance();
    final value = prefs.getString(key);
    debugPrint(
      '[APP_STORAGE.getString] key=$key result=${value != null ? '${value.length} bytes' : 'null'}',
    );
    return value;
  }

  Future<void> setString(String key, String value) async {
    final prefs = await _getInstance();
    final success = await prefs.setString(key, value);
    debugPrint(
      '[APP_STORAGE.setString] key=$key value_length=${value.length} success=$success',
    );
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
    debugPrint('[APP_STORAGE.remove] key=$key');
  }

  Future<void> clear() async {
    final prefs = await _getInstance();
    await prefs.clear();
    debugPrint('[APP_STORAGE.clear] All keys removed');
  }
}
