import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:preconnect/tools/app_log.dart';
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
  static final Map<String, String> _memCache = {};
  static Directory? _cacheDir;
  static Future<void> _pending = Future<void>.value();

  static Future<void> initialize({Directory? cacheDirectory}) async {
    await _pending;
    _memCache.clear();
    _webCache.clear();
    if (kIsWeb) {
      try {
        final all = await webExtensionStorageGetAll();
        _webCache.addAll(all);
      } catch (_) {}
      return;
    }
    try {
      _prefs = await SharedPreferences.getInstance();
      if (cacheDirectory != null) {
        _cacheDir = cacheDirectory;
      } else {
        await _initCacheDir();
      }
      await _migrateLargeEntries();
    } catch (_) {}
  }

  static Future<void> _initCacheDir() async {
    if (kIsWeb) return;
    try {
      final base = await AppPaths.supportDirectory();
      _cacheDir = Directory('${base.path}/kvcache');
      if (!_cacheDir!.existsSync()) {
        _cacheDir!.createSync(recursive: true);
      }
    } catch (error) {
      _cacheDir = null;
    }
  }

  static Future<void> _migrateLargeEntries() async {
    final prefs = _prefs;
    if (prefs == null) return;
    try {
      final keys = prefs.getKeys().toList();
      for (final key in keys) {
        try {
          final val = prefs.getString(key);
          if (val == null || val.startsWith(_kFileCacheMarker)) continue;
          if (val.length > _kLargeValueThreshold) {
            await instance.setString(key, val);
          }
        } catch (_) {}
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
    if (_cacheDir == null || !_cacheDir!.existsSync()) {
      await _initCacheDir();
    }
    final file = _fileForKey(key);
    if (file == null) throw StateError('Cache directory is unavailable.');
    final staging = await file.parent.createTemp('.cache_');
    try {
      final temporary = File('${staging.path}/value');
      await temporary.writeAsBytes(
        gzip.encode(utf8.encode(value)),
        flush: true,
      );
      await temporary.rename(file.path);
    } finally {
      await staging.delete(recursive: true);
    }
  }

  static String _decodeFileBytes(List<int> bytes) {
    final compressed =
        bytes.length >= 2 && bytes[0] == 0x1f && bytes[1] == 0x8b;
    return utf8.decode(compressed ? gzip.decode(bytes) : bytes);
  }

  static Future<String?> _readFromFile(String key) async {
    try {
      final file = _fileForKey(key);
      if (file == null || !file.existsSync()) return null;
      return _decodeFileBytes(await file.readAsBytes());
    } catch (e) {
      unawaited(AppLog.write('AppStorage Read Error ($key): $e'));
      return null;
    }
  }

  static String? _readFromFileSync(String key) {
    try {
      final file = _fileForKey(key);
      if (file == null || !file.existsSync()) return null;
      return _decodeFileBytes(file.readAsBytesSync());
    } catch (_) {
      return null;
    }
  }

  static Future<void> _deleteFile(String key) async {
    final file = _fileForKey(key);
    if (file != null && file.existsSync()) await file.delete();
  }

  Future<String?> getString(String key) async {
    if (kIsWeb) return _webCache[key];
    if (_memCache.containsKey(key)) return _memCache[key];
    final prefs = await _getInstance();
    final raw = prefs.getString(key);
    if (raw == null) return null;
    if (raw.startsWith(_kFileCacheMarker)) {
      final val = await _readFromFile(key);
      if (val != null) _memCache[key] = val;
      return val;
    }
    _memCache[key] = raw;
    return raw;
  }

  static Future<void> _persist(Future<void> Function() operation) {
    final result = _pending.then((_) async {
      try {
        await operation();
      } catch (_) {
        await _prefs?.reload();
        rethrow;
      }
    });
    _pending = result.then(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return result;
  }

  Future<void> setString(String key, String value) => _persist(() async {
    try {
      if (kIsWeb) {
        await webExtensionStorageSet(key, value);
        _webCache[key] = value;
      } else {
        final prefs = await _getInstance();
        if (value.length > _kLargeValueThreshold) {
          await _writeToFile(key, value);
          if (prefs.getString(key) != '$_kFileCacheMarker$key' &&
              !await prefs.setString(key, '$_kFileCacheMarker$key')) {
            throw StateError('Cache marker could not be persisted.');
          }
        } else {
          if (!await prefs.setString(key, value)) {
            throw StateError('Setting could not be persisted.');
          }
          await _deleteFile(key);
        }
      }
      _memCache[key] = value;
    } catch (e) {
      unawaited(AppLog.write('AppStorage setString Error ($key): $e'));
      rethrow;
    }
  });

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
    if (_memCache.containsKey(key)) return true;
    try {
      final prefs = await _getInstance();
      return prefs.containsKey(key);
    } catch (_) {
      return false;
    }
  }

  Future<void> remove(String key) => _persist(() async {
    try {
      if (kIsWeb) {
        await webExtensionStorageSet(key, null);
        _webCache.remove(key);
      } else {
        final prefs = await _getInstance();
        if (!await prefs.remove(key)) {
          throw StateError('Setting could not be removed.');
        }
        await _deleteFile(key);
      }
      _memCache.remove(key);
    } catch (e) {
      unawaited(AppLog.write('AppStorage remove Error ($key): $e'));
      rethrow;
    }
  });

  Future<void> clear() => _persist(() async {
    try {
      if (kIsWeb) {
        await webExtensionStorageRemoveKeys(_webCache.keys.toList());
        _webCache.clear();
      } else {
        final prefs = await _getInstance();
        if (!await prefs.clear()) {
          throw StateError('Settings could not be cleared.');
        }
        _memCache.clear();
        final cacheDir = _cacheDir;
        if (cacheDir != null && cacheDir.existsSync()) {
          for (final entity in cacheDir.listSync()) {
            await entity.delete(recursive: true);
          }
        }
      }
      _memCache.clear();
    } catch (e) {
      unawaited(AppLog.write('AppStorage clear Error: $e'));
      rethrow;
    }
  });

  String? getStringSync(String key) {
    if (kIsWeb) return _webCache[key];
    if (_memCache.containsKey(key)) return _memCache[key];
    final raw = _prefs?.getString(key);
    if (raw == null) return null;
    if (raw.startsWith(_kFileCacheMarker)) {
      final val = _readFromFileSync(key);
      if (val != null) _memCache[key] = val;
      return val;
    }
    _memCache[key] = raw;
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
}
