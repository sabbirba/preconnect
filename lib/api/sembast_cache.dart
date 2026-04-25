import 'dart:convert';

import 'package:sembast/sembast_io.dart';
import 'package:preconnect/tools/app_paths.dart';

class SembastCache {
  SembastCache._internal();
  static final SembastCache _instance = SembastCache._internal();
  factory SembastCache() => _instance;

  static const String _dbName = 'app_structured_cache.db';
  final StoreRef<String, Object?> _store = StoreRef<String, Object?>(
    'structured_cache',
  );

  Database? _db;

  Future<Database> _openDb() async {
    final existing = _db;
    if (existing != null) return existing;
    final dir = await AppPaths.documentsDirectory();
    final dbPath = '${dir.path}/$_dbName';
    final db = await databaseFactoryIo.openDatabase(dbPath);
    _db = db;
    return db;
  }

  Future<String?> getString(String key) async {
    try {
      final db = await _openDb();
      final value = await _store.record(key).get(db);
      return value is String ? value : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> setString(String key, String value) async {
    try {
      final db = await _openDb();
      await _store.record(key).put(db, value);
    } catch (_) {}
  }

  Future<void> setStringMap(Map<String, String> values) async {
    if (values.isEmpty) return;
    try {
      final db = await _openDb();
      await db.transaction((txn) async {
        for (final entry in values.entries) {
          await _store.record(entry.key).put(txn, entry.value);
        }
      });
    } catch (_) {}
  }

  Future<Map<String, String?>> getStringMap(Set<String> keys) async {
    final output = <String, String?>{};
    if (keys.isEmpty) return output;
    try {
      final db = await _openDb();
      for (final key in keys) {
        final value = await _store.record(key).get(db);
        output[key] = value is String ? value : null;
      }
    } catch (_) {
      for (final key in keys) {
        output[key] = null;
      }
    }
    return output;
  }

  Future<void> setJson(String key, dynamic value) async {
    await setString(key, jsonEncode(value));
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
    try {
      final db = await _openDb();
      await _store.record(key).delete(db);
    } catch (_) {}
  }

  Future<void> clearAll() async {
    try {
      final db = await _openDb();
      await _store.delete(db);
    } catch (_) {}
  }
}

Future<String?> readCachedSembastStringWithFallback({
  required String key,
  required bool fromFetch,
  required Future<String?> Function() onCacheMiss,
}) async {
  final cached = await SembastCache().getString(key);
  if (cached == null || cached.isEmpty) {
    if (fromFetch) return null;
    return onCacheMiss();
  }
  return cached;
}

Future<T?> readCachedSembastJsonMapWithFallback<T>({
  required String key,
  required bool fromFetch,
  required T? Function(Map<String, dynamic> value) decoder,
  required Future<T?> Function() onCacheMiss,
}) async {
  final cached = await SembastCache().getJsonMap(key);
  if (cached == null) {
    if (fromFetch) return null;
    return onCacheMiss();
  }
  try {
    return decoder(cached);
  } catch (_) {
    if (fromFetch) return null;
    return onCacheMiss();
  }
}
