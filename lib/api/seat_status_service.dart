import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:preconnect/api/api_client.dart';
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/model/seat_status_info.dart';
import 'package:sembast/sembast_io.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SeatStatusService {
  SeatStatusService._internal();

  static final SeatStatusService _instance = SeatStatusService._internal();
  factory SeatStatusService() => _instance;

  final ApiClient _client = ApiClient();
  Database? _db;
  Map<int, int>? _seatMapSnapshot;

  static const String _dbName = 'seat_status_cache.db';
  static const String _detailsTsKey = 'details_ts';
  static const String _seatMapTsKey = 'seat_map_ts';
  static const String _seatMapEtagKey = 'seat_map_etag';
  static const String _detailsEtagPrefix = 'details_etag_';
  static const String _legacyCleanupDoneKey = 'seat_status_sp_cleanup_done_v1';
  static const List<String> _legacySharedPrefsKeys = <String>[
    'seat_status_details_cache_v1',
    'seat_status_details_cache_ts_v1',
    'seat_status_map_cache_v1',
    'seat_status_map_cache_ts_v1',
  ];

  final StoreRef<String, Object?> _metaStore = StoreRef<String, Object?>(
    'seat_status_meta',
  );
  final StoreRef<int, Object?> _seatMapStore = intMapStoreFactory.store(
    'seat_status_map',
  );
  final StoreRef<int, Object?> _detailsStore = intMapStoreFactory.store(
    'seat_status_details',
  );

  Future<Map<int, int>> fetchSeatStatusMap() async {
    final db = await _openDb();
    final etag = await _metaStore.record(_seatMapEtagKey).get(db) as String?;
    final response = await _client.authenticatedGet(
      ApiConfig.seatStatusUrl,
      additionalHeaders: _ifNoneMatchHeader(etag),
      acceptedStatusCodes: const <int>{200, 304},
    );
    if (response.statusCode == 304) {
      final cached = await _getSeatMapSnapshot(db);
      return Map<int, int>.from(cached);
    }
    final nextEtag = _extractEtag(response.headers);
    if (nextEtag != null && nextEtag.isNotEmpty) {
      await _metaStore.record(_seatMapEtagKey).put(db, nextEtag);
    }
    return compute(_parseSeatMapFromBody, response.body);
  }

  Future<Map<int, int>> loadCachedSeatMap({
    Duration maxAge = const Duration(hours: 1),
  }) async {
    try {
      final db = await _openDb();
      final ts = await _metaStore.record(_seatMapTsKey).get(db) as int?;
      if (ts == null) return const <int, int>{};
      final age = DateTime.now().difference(
        DateTime.fromMillisecondsSinceEpoch(ts),
      );
      if (age > maxAge) return const <int, int>{};
      final snapshots = await _seatMapStore.find(db);
      if (snapshots.isEmpty) return const <int, int>{};
      final result = <int, int>{};
      for (final snap in snapshots) {
        final value = snap.value;
        if (value is int) {
          result[snap.key] = value;
        } else {
          final parsed = int.tryParse('$value');
          if (parsed != null) {
            result[snap.key] = parsed;
          }
        }
      }
      return result;
    } catch (_) {
      return const <int, int>{};
    }
  }

  Future<SeatStatusDetailsResponse?> fetchSectionDetails(int sectionId) async {
    final db = await _openDb();
    final etagKey = _detailsEtagKey(sectionId);
    final etag = await _metaStore.record(etagKey).get(db) as String?;
    final response = await _client.authenticatedGet(
      ApiConfig.sectionDetailsUrl(sectionId),
      additionalHeaders: _ifNoneMatchHeader(etag),
      acceptedStatusCodes: const <int>{200, 304},
    );
    if (response.statusCode == 304) {
      return _loadCachedDetailById(db, sectionId);
    }

    final parsed = await compute(_parseDetailsFromBody, response.body);
    if (parsed == null) return null;

    final nextEtag = _extractEtag(response.headers);
    await _detailsStore.record(sectionId).put(db, parsed.toJson());
    await _metaStore.record(_detailsTsKey).put(db, _nowMs());
    if (nextEtag != null && nextEtag.isNotEmpty) {
      await _metaStore.record(etagKey).put(db, nextEtag);
    }
    return parsed;
  }

  Future<Map<int, SeatStatusDetailsResponse>> loadCachedDetails({
    Duration maxAge = const Duration(hours: 1),
  }) async {
    try {
      final db = await _openDb();
      final ts = await _metaStore.record(_detailsTsKey).get(db) as int?;
      if (ts == null) return const <int, SeatStatusDetailsResponse>{};
      final age = DateTime.now().difference(
        DateTime.fromMillisecondsSinceEpoch(ts),
      );
      if (age > maxAge) return const <int, SeatStatusDetailsResponse>{};
      final snapshots = await _detailsStore.find(db);
      if (snapshots.isEmpty) return const <int, SeatStatusDetailsResponse>{};
      final raw = <String, dynamic>{};
      for (final snap in snapshots) {
        if (snap.value is Map<String, dynamic>) {
          raw[snap.key.toString()] = snap.value;
        } else if (snap.value is Map) {
          raw[snap.key.toString()] = (snap.value as Map)
              .cast<String, dynamic>();
        }
      }
      return _parseCachedDetailsFromMap(raw);
    } catch (_) {
      return const <int, SeatStatusDetailsResponse>{};
    }
  }

  Future<void> saveSeatMapCacheIfChanged(Map<int, int> seatMap) async {
    if (seatMap.isEmpty) return;
    try {
      final db = await _openDb();
      final existing = await _getSeatMapSnapshot(db);

      final changed = <MapEntry<int, int>>[];
      for (final entry in seatMap.entries) {
        if (existing[entry.key] != entry.value) {
          changed.add(entry);
        }
      }
      final removed = existing.keys
          .where((key) => !seatMap.containsKey(key))
          .toList();
      if (changed.isEmpty && removed.isEmpty) return;

      await db.transaction((txn) async {
        for (final entry in changed) {
          await _seatMapStore.record(entry.key).put(txn, entry.value);
        }
        for (final key in removed) {
          await _seatMapStore.record(key).delete(txn);
        }
        await _metaStore.record(_seatMapTsKey).put(txn, _nowMs());
      });
      _seatMapSnapshot = Map<int, int>.from(seatMap);
    } catch (_) {}
  }

  Future<Database> _openDb() async {
    final existing = _db;
    if (existing != null) return existing;
    final dir = await getApplicationDocumentsDirectory();
    final dbPath = '${dir.path}/$_dbName';
    final db = await databaseFactoryIo.openDatabase(dbPath);
    await _cleanupLegacySharedPrefsCacheOnce();
    _db = db;
    return db;
  }

  int _nowMs() => DateTime.now().millisecondsSinceEpoch;

  Future<void> _cleanupLegacySharedPrefsCacheOnce() async {
    try {
      final prefs = SharedPreferencesAsync();
      final done = await prefs.getBool(_legacyCleanupDoneKey);
      if (done == true) return;
      for (final key in _legacySharedPrefsKeys) {
        await prefs.remove(key);
      }
      await prefs.setBool(_legacyCleanupDoneKey, true);
    } catch (_) {}
  }

  Future<Map<int, int>> _getSeatMapSnapshot(Database db) async {
    final cached = _seatMapSnapshot;
    if (cached != null) return cached;
    final snapshots = await _seatMapStore.find(db);
    final existing = <int, int>{};
    for (final snap in snapshots) {
      final value = snap.value;
      if (value is int) {
        existing[snap.key] = value;
      } else {
        final parsed = int.tryParse('$value');
        if (parsed != null) {
          existing[snap.key] = parsed;
        }
      }
    }
    _seatMapSnapshot = existing;
    return existing;
  }

  Future<SeatStatusDetailsResponse?> _loadCachedDetailById(
    Database db,
    int sectionId,
  ) async {
    try {
      final raw = await _detailsStore.record(sectionId).get(db);
      if (raw is Map<String, dynamic>) {
        return SeatStatusDetailsResponse.fromJson(raw);
      }
      if (raw is Map) {
        return SeatStatusDetailsResponse.fromJson(raw.cast<String, dynamic>());
      }
    } catch (_) {}
    return null;
  }

  String _detailsEtagKey(int sectionId) => '$_detailsEtagPrefix$sectionId';

  Map<String, String> _ifNoneMatchHeader(String? etag) {
    final value = (etag ?? '').trim();
    if (value.isEmpty) return const <String, String>{};
    return <String, String>{'If-None-Match': value};
  }

  String? _extractEtag(Map<String, String> headers) {
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == 'etag') {
        final value = entry.value.trim();
        if (value.isNotEmpty) return value;
      }
    }
    return null;
  }
}

Map<int, int> _parseSeatMapFromBody(String body) {
  final decoded = jsonDecode(body);
  if (decoded is! Map) return const <int, int>{};
  final result = <int, int>{};
  for (final entry in decoded.entries) {
    final key = int.tryParse(entry.key);
    final value = int.tryParse('${entry.value}');
    if (key != null && value != null) {
      result[key] = value;
    }
  }
  return result;
}

SeatStatusDetailsResponse? _parseDetailsFromBody(String body) {
  final decoded = jsonDecode(body);
  if (decoded is! Map<String, dynamic>) return null;
  return SeatStatusDetailsResponse.fromJson(decoded);
}

Map<int, SeatStatusDetailsResponse> _parseCachedDetailsFromMap(
  Map<String, dynamic> decoded,
) {
  final result = <int, SeatStatusDetailsResponse>{};
  for (final entry in decoded.entries) {
    final key = int.tryParse(entry.key);
    if (key == null) continue;
    if (entry.value is! Map) continue;
    try {
      result[key] = SeatStatusDetailsResponse.fromJson(
        (entry.value as Map).cast<String, dynamic>(),
      );
    } catch (_) {}
  }
  return result;
}
