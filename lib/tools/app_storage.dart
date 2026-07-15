import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:preconnect/tools/platform_stub.dart'
    if (dart.library.js_interop) 'package:preconnect/tools/storage_web.dart';

class AppStorage {
  AppStorage._();

  static final AppStorage instance = AppStorage._();
  static SharedPreferences? _prefs;
  static final Map<String, String> _webCache = {};

  static Future<void> initialize() async {
    if (kIsWeb) {
      final all = await webExtensionStorageGetAll();
      _webCache.addAll(all);
      return;
    }
    _prefs = await SharedPreferences.getInstance();
  }

  static Future<SharedPreferences> _getInstance() async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  Future<String?> getString(String key) async {
    if (kIsWeb) {
      return _webCache[key];
    }
    final prefs = await _getInstance();
    final value = prefs.getString(key);
    return value;
  }

  Future<void> setString(String key, String value) async {
    if (kIsWeb) {
      _webCache[key] = value;
      await webExtensionStorageSet(key, value);
      return;
    }
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
    if (kIsWeb) {
      return _webCache.containsKey(key);
    }
    final prefs = await _getInstance();
    return prefs.containsKey(key);
  }

  Future<void> remove(String key) async {
    if (kIsWeb) {
      _webCache.remove(key);
      await webExtensionStorageSet(key, null);
      return;
    }
    final prefs = await _getInstance();
    await prefs.remove(key);
  }

  Future<void> clear() async {
    if (kIsWeb) {
      final keys = _webCache.keys.toList();
      _webCache.clear();
      await webExtensionStorageRemoveKeys(keys);
      return;
    }
    final prefs = await _getInstance();
    await prefs.clear();
  }

  Future<void> clearExcept(Set<String> keepKeys) async {
    if (kIsWeb) {
      final keysToRemove = _webCache.keys
          .where((k) => !keepKeys.contains(k))
          .toList();
      for (final key in keysToRemove) {
        _webCache.remove(key);
      }
      await webExtensionStorageRemoveKeys(keysToRemove);
      return;
    }
    final prefs = await _getInstance();
    final keys = prefs.getKeys();
    for (final key in keys) {
      if (keepKeys.contains(key)) continue;
      await prefs.remove(key);
    }
  }

  String? getStringSync(String key) {
    if (kIsWeb) {
      return _webCache[key];
    }
    return _prefs?.getString(key);
  }

  bool? getBoolSync(String key) {
    final raw = getStringSync(key);
    if (raw == null || raw.isEmpty) return null;
    return raw == 'true';
  }

  int? getIntSync(String key) {
    final raw = getStringSync(key);
    return raw == null ? null : int.tryParse(raw);
  }

  List<String>? getStringListSync(String key) {
    final raw = getStringSync(key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return null;
      return decoded.map((e) => '$e').toList();
    } catch (_) {
      return null;
    }
  }
}
