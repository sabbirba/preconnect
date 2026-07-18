import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:preconnect/tools/app_paths.dart';
import 'package:preconnect/tools/platform_stub.dart'
    if (dart.library.js_interop) 'package:preconnect/tools/storage_web.dart';

const int _kLargeValueThreshold = 256 * 1024;
const String _kFileCacheMarker = '__fscache__:';

class AppStorage {
  AppStorage._();

  static final AppStorage instance = AppStorage._();
  static SharedPreferences? _prefs;
  static final Map<String, String> _webCache = {};
  static Directory? _cacheDir;

  static Future<void> initialize() async {
    if (kIsWeb) {
      final all = await webExtensionStorageGetAll();
      _webCache.addAll(all);
      return;
    }
    _prefs = await SharedPreferences.getInstance();
    await _initCacheDir();
    await _migrateLargeEntries();
  }

  static Future<void> _initCacheDir() async {
    if (kIsWeb) return;
    try {
      final base = await AppPaths.supportDirectory();
      _cacheDir = Directory('${base.path}/kvcache');
      if (!_cacheDir!.existsSync()) {
        _cacheDir!.createSync(recursive: true);
      }
    } catch (_) {}
  }

  static Future<void> _migrateLargeEntries() async {
    final prefs = _prefs;
    if (prefs == null) return;
    try {
      final keys = prefs.getKeys().toList();
      for (final key in keys) {
        final val = prefs.getString(key);
        if (val == null) continue;
        if (val.startsWith(_kFileCacheMarker)) continue;
        if (val.length > _kLargeValueThreshold) {
          await _writeToFile(key, val);
          await prefs.setString(key, '$_kFileCacheMarker$key');
        }
      }
    } catch (_) {}
  }

  static Future<SharedPreferences> _getInstance() async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  static File? _fileForKey(String key) {
    final dir = _cacheDir;
    if (dir == null) return null;
    final safe = key.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
    return File('${dir.path}/$safe.json');
  }

  static Future<void> _writeToFile(String key, String value) async {
    try {
      if (_cacheDir == null) await _initCacheDir();
      final file = _fileForKey(key);
      if (file == null) return;
      await file.writeAsString(value, flush: true);
    } catch (_) {}
  }

  static Future<String?> _readFromFile(String key) async {
    try {
      final file = _fileForKey(key);
      if (file == null || !file.existsSync()) return null;
      return await file.readAsString();
    } catch (_) {
      return null;
    }
  }

  static String? _readFromFileSync(String key) {
    try {
      final file = _fileForKey(key);
      if (file == null || !file.existsSync()) return null;
      return file.readAsStringSync();
    } catch (_) {
      return null;
    }
  }

  static Future<void> _deleteFile(String key) async {
    try {
      final file = _fileForKey(key);
      if (file != null && file.existsSync()) {
        await file.delete();
      }
    } catch (_) {}
  }

  Future<String?> getString(String key) async {
    if (kIsWeb) return _webCache[key];
    final prefs = await _getInstance();
    final raw = prefs.getString(key);
    if (raw == null) return null;
    if (raw.startsWith(_kFileCacheMarker)) {
      return _readFromFile(key);
    }
    return raw;
  }

  Future<void> setString(String key, String value) async {
    if (kIsWeb) {
      _webCache[key] = value;
      await webExtensionStorageSet(key, value);
      return;
    }
    final prefs = await _getInstance();
    if (value.length > _kLargeValueThreshold) {
      await _writeToFile(key, value);
      await prefs.setString(key, '$_kFileCacheMarker$key');
    } else {
      await _deleteFile(key);
      await prefs.setString(key, value);
    }
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
    if (kIsWeb) return _webCache.containsKey(key);
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
    await _deleteFile(key);
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
    final keys = prefs.getKeys().toList();
    for (final key in keys) {
      await _deleteFile(key);
    }
    await prefs.clear();
    try {
      _cacheDir?.listSync().forEach((f) => f.deleteSync());
    } catch (_) {}
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
      await _deleteFile(key);
      await prefs.remove(key);
    }
  }

  String? getStringSync(String key) {
    if (kIsWeb) return _webCache[key];
    final raw = _prefs?.getString(key);
    if (raw == null) return null;
    if (raw.startsWith(_kFileCacheMarker)) {
      return _readFromFileSync(key);
    }
    return raw;
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
