import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:preconnect/api/api_client.dart';
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/model/seat_status_info.dart';
import 'package:sembast/sembast_io.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SeatStatusService {
  static const List<String> _detailsWrapperKeys = <String>[
    'data',
    'sections',
    'details',
    'items',
    'results',
  ];
  static const List<String> _seatMapWrapperKeys = <String>[
    'data',
    'seatStatus',
    'sections',
    'items',
    'results',
  ];
  static const Set<String> _invalidInitials = <String>{
    'TBA',
    'NULL',
    'N/A',
    '--',
  };

  SeatStatusService._internal();

  static final SeatStatusService _instance = SeatStatusService._internal();
  factory SeatStatusService() => _instance;

  Database? _db;
  Map<int, SeatStatusDetailsResponse>? _detailsSnapshot;
  int? _detailsSnapshotTs;
  Map<String, SeatStatusStaffInfo>? _staffSnapshot;
  final ApiClient _client = ApiClient();
  final Map<String, SeatStatusStaffInfo> _staffInfoByInitialCache =
      <String, SeatStatusStaffInfo>{};
  final Map<String, Future<SeatStatusStaffInfo?>> _staffInfoInFlight =
      <String, Future<SeatStatusStaffInfo?>>{};
  final ValueNotifier<bool> isSavingDetailsCache = ValueNotifier<bool>(false);

  String get _proxyBase {
    final base = ApiConfig.seatStatusProxyBase.trim();
    if (base.isEmpty) {
      throw StateError('Missing Seat Status proxy base URL');
    }
    return base;
  }

  String get seatStatusStreamUrl {
    return '$_proxyBase/seat-status/stream';
  }

  String get _seatStatusUrl {
    return '$_proxyBase/seat-status';
  }

  String _sectionDetailsUrl(int sectionId) {
    return '$_proxyBase/sections/$sectionId/details';
  }

  String get _allSectionsDetailsUrl {
    return '$_proxyBase/sections/details';
  }

  String _staffByInitialUrl(String initial) {
    return '$_proxyBase/staff/${Uri.encodeComponent(initial)}';
  }

  static const String _dbName = 'seat_status_cache.db';
  static const String _detailsTsKey = 'details_ts';
  static const String _freeLabsSlotsKey = 'free_labs_slots_v1';
  static const String _freeLabsSlotsDateKey = 'free_labs_slots_date_v1';
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
  final StoreRef<int, Object?> _detailsStore = intMapStoreFactory.store(
    'seat_status_details',
  );
  final StoreRef<int, Object?> _alertsStore = intMapStoreFactory.store(
    'seat_status_alerts',
  );
  final StoreRef<String, Object?> _staffStore = StoreRef<String, Object?>(
    'seat_status_staff',
  );

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
      if (_detailsSnapshotTs == ts && _detailsSnapshot != null) {
        return Map<int, SeatStatusDetailsResponse>.from(_detailsSnapshot!);
      }
      final snapshot = await _getDetailsSnapshot(db);
      _detailsSnapshotTs = ts;
      _detailsSnapshot = Map<int, SeatStatusDetailsResponse>.from(snapshot);
      if (snapshot.isEmpty) return const <int, SeatStatusDetailsResponse>{};
      return Map<int, SeatStatusDetailsResponse>.from(snapshot);
    } catch (_) {
      return const <int, SeatStatusDetailsResponse>{};
    }
  }

  Future<void> saveDetailsCache(
    Map<int, SeatStatusDetailsResponse> detailsBySection,
  ) async {
    if (detailsBySection.isEmpty) return;
    isSavingDetailsCache.value = true;
    try {
      final db = await _openDb();
      await db.transaction((txn) async {
        var wroteAny = false;
        for (final entry in detailsBySection.entries) {
          final nextJson = entry.value.toJson();
          final existingRaw = await _detailsStore.record(entry.key).get(txn);
          Map<String, dynamic>? existingJson;
          if (existingRaw is Map<String, dynamic>) {
            existingJson = existingRaw;
          } else if (existingRaw is Map) {
            existingJson = existingRaw.cast<String, dynamic>();
          }
          if (existingJson != null && _jsonDeepEqual(existingJson, nextJson)) {
            continue;
          }
          await _detailsStore.record(entry.key).put(txn, nextJson);
          wroteAny = true;
        }
        if (wroteAny) {
          await _metaStore.record(_detailsTsKey).put(txn, _nowMs());
        }
      });
      _detailsSnapshot = null;
      _detailsSnapshotTs = null;
    } catch (_) {
    } finally {
      isSavingDetailsCache.value = false;
    }
  }

  Future<List<Map<String, dynamic>>> loadCachedFreeLabsSlots({
    required String dateKey,
  }) async {
    try {
      final db = await _openDb();
      final cachedDate =
          await _metaStore.record(_freeLabsSlotsDateKey).get(db) as String?;
      if (cachedDate != dateKey) return const <Map<String, dynamic>>[];
      final raw = await _metaStore.record(_freeLabsSlotsKey).get(db);
      if (raw is! List) return const <Map<String, dynamic>>[];
      return raw
          .whereType<Map>()
          .map((item) => item.cast<String, dynamic>())
          .toList();
    } catch (_) {
      return const <Map<String, dynamic>>[];
    }
  }

  Future<void> saveFreeLabsSlotsCacheIfChanged({
    required String dateKey,
    required List<Map<String, dynamic>> slots,
  }) async {
    try {
      final db = await _openDb();
      final currentDate =
          await _metaStore.record(_freeLabsSlotsDateKey).get(db) as String?;
      final currentRaw = await _metaStore.record(_freeLabsSlotsKey).get(db);
      final currentSlots = currentRaw is List
          ? currentRaw
                .whereType<Map>()
                .map((item) => item.cast<String, dynamic>())
                .toList()
          : const <Map<String, dynamic>>[];
      final hasSameDate = currentDate == dateKey;
      final hasSameSlots = jsonEncode(currentSlots) == jsonEncode(slots);
      if (hasSameDate && hasSameSlots) return;
      await db.transaction((txn) async {
        await _metaStore.record(_freeLabsSlotsKey).put(txn, slots);
        await _metaStore.record(_freeLabsSlotsDateKey).put(txn, dateKey);
      });
    } catch (_) {}
  }

  Future<Map<int, SeatAlertConfig>> loadSeatAlertConfigs() async {
    try {
      final db = await _openDb();
      final records = await _alertsStore.find(db);
      final output = <int, SeatAlertConfig>{};
      for (final record in records) {
        final raw = record.value;
        if (raw is! Map) continue;
        final key = record.key;
        try {
          final config = SeatAlertConfig.fromJson(
            key,
            raw.cast<String, dynamic>(),
          );
          if (config.hasAnyRule) {
            output[key] = config;
          }
        } catch (_) {}
      }
      return output;
    } catch (_) {
      return const <int, SeatAlertConfig>{};
    }
  }

  Future<void> saveSeatAlertConfig(SeatAlertConfig config) async {
    try {
      final db = await _openDb();
      if (!config.hasAnyRule) {
        await _alertsStore.record(config.sectionId).delete(db);
        return;
      }
      await _alertsStore.record(config.sectionId).put(db, config.toJson());
    } catch (_) {}
  }

  Future<void> removeSeatAlertConfig(int sectionId) async {
    try {
      final db = await _openDb();
      await _alertsStore.record(sectionId).delete(db);
    } catch (_) {}
  }

  Future<Map<int, SeatStatusDetailsResponse>>
  fetchAllSectionsDetailsFromApi() async {
    final bundled = await _fetchAllSectionsDetailsBundle();
    if (bundled.isNotEmpty) {
      return bundled;
    }
    final seatMap = await _fetchSeatMapFromApi();
    if (seatMap.isEmpty) return const <int, SeatStatusDetailsResponse>{};
    final allDetails = await _fetchSectionDetailsDirect(
      seatMap.keys.toList()..sort((a, b) => a - b),
    );
    await _saveDetailsIfAny(allDetails);
    return allDetails;
  }

  Future<Map<int, int>> _fetchSeatMapFromApi() async {
    final raw = await _fetchJson(_seatStatusUrl);
    return _parseSeatMapResponse(raw);
  }

  Future<void> preloadSeatStatusCache({int detailConcurrency = 8}) async {
    try {
      final db = await _openDb();
      final allDetails = await fetchAllSectionsDetailsFromApi();
      if (allDetails.isEmpty) return;
      final sectionIds = allDetails.keys.toSet();
      final existingDetails = await _detailsStore.findKeys(db);
      final cachedIds = existingDetails.toSet();
      final stale = cachedIds.where((id) => !sectionIds.contains(id)).toList()
        ..sort((a, b) => a.compareTo(b));

      if (stale.isNotEmpty) {
        await db.transaction((txn) async {
          for (final sectionId in stale) {
            await _detailsStore.record(sectionId).delete(txn);
          }
        });
        _detailsSnapshot = null;
        _detailsSnapshotTs = null;
      }

      final initials = _collectFacultyInitials(allDetails.values);
      if (initials.isNotEmpty) {
        await resolveStaffInfoByInitials(
          initials,
          concurrency: detailConcurrency <= 0 ? 6 : detailConcurrency,
        );
      }
    } catch (_) {}
  }

  Future<void> clearAll() async {
    try {
      final db = await _openDb();
      await db.transaction((txn) async {
        await _metaStore.delete(txn);
        await _detailsStore.delete(txn);
        await _alertsStore.delete(txn);
        await _staffStore.delete(txn);
      });
    } catch (_) {}
    _detailsSnapshot = null;
    _detailsSnapshotTs = null;
    _staffSnapshot = null;
    _staffInfoByInitialCache.clear();
    _staffInfoInFlight.clear();
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

  Future<Map<String, SeatStatusStaffInfo>> resolveStaffInfoByInitials(
    Iterable<String> initials, {
    int concurrency = 6,
  }) async {
    final requested = _normalizedInitials(initials);
    if (requested.isEmpty) return const <String, SeatStatusStaffInfo>{};

    final chunkSize = concurrency <= 0 ? 6 : concurrency;
    var index = 0;
    while (index < requested.length) {
      final end = (index + chunkSize > requested.length)
          ? requested.length
          : index + chunkSize;
      final batch = requested.sublist(index, end);
      await Future.wait(batch.map((key) => _resolveStaffInfoForInitial(key)));
      index = end;
    }

    final output = <String, SeatStatusStaffInfo>{};
    for (final key in requested) {
      final value = _staffInfoByInitialCache[key];
      if (value == null) continue;
      output[key] = value;
    }
    return output;
  }

  Future<SeatStatusStaffInfo?> _resolveStaffInfoForInitial(
    String initial,
  ) async {
    final key = initial.trim().toUpperCase();
    if (!_isMeaningfulInitial(key)) return null;
    final cached = _staffInfoByInitialCache[key];
    if (cached != null) return cached;

    final fromDb = await _loadStaffInfoFromDb(key);
    if (fromDb != null) {
      _staffInfoByInitialCache[key] = fromDb;
      return fromDb;
    }

    final existing = _staffInfoInFlight[key];
    if (existing != null) return existing;

    final future = _fetchStaffInfoByInitialFromProxy(key);
    _staffInfoInFlight[key] = future;
    try {
      final info = await future;
      if (info != null) {
        _staffInfoByInitialCache[key] = info;
        await _saveStaffInfoToDb(info);
      }
      return info;
    } finally {
      _staffInfoInFlight.remove(key);
    }
  }

  Future<SeatStatusStaffInfo?> _fetchStaffInfoByInitialFromProxy(
    String initial,
  ) async {
    final url = _staffByInitialUrl(initial);
    try {
      final response = await _client.publicGet(
        url,
        acceptedStatusCodes: const <int>{200, 404},
      );
      if (response.statusCode != 200) return null;
      final raw = jsonDecode(response.body);
      if (raw is! Map<String, dynamic>) return null;
      return SeatStatusStaffInfo.fromJson(raw);
    } catch (_) {
      return null;
    }
  }

  bool _isMeaningfulInitial(String value) {
    if (value.trim().isEmpty) return false;
    return !_invalidInitials.contains(value.trim().toUpperCase());
  }

  Future<SeatStatusStaffInfo?> _loadStaffInfoFromDb(String initial) async {
    try {
      final db = await _openDb();
      final snapshot = await _getStaffSnapshot(db);
      return snapshot[initial];
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveStaffInfoToDb(SeatStatusStaffInfo info) async {
    try {
      final db = await _openDb();
      final key = info.shortName.toUpperCase();
      await _staffStore.record(key).put(db, info.toJson());
      _staffSnapshot ??= <String, SeatStatusStaffInfo>{};
      _staffSnapshot![key] = info;
    } catch (_) {}
  }

  Future<Map<int, SeatStatusDetailsResponse>> _getDetailsSnapshot(
    Database db,
  ) async {
    final cached = _detailsSnapshot;
    if (cached != null) return cached;
    final snapshots = await _detailsStore.find(db);
    if (snapshots.isEmpty) {
      _detailsSnapshot = <int, SeatStatusDetailsResponse>{};
      return _detailsSnapshot!;
    }
    final raw = <String, dynamic>{};
    for (final snap in snapshots) {
      if (snap.value is Map<String, dynamic>) {
        raw[snap.key.toString()] = snap.value;
      } else if (snap.value is Map) {
        raw[snap.key.toString()] = (snap.value as Map).cast<String, dynamic>();
      }
    }
    _detailsSnapshot = _parseCachedDetailsFromMap(raw);
    return _detailsSnapshot!;
  }

  Future<Map<String, SeatStatusStaffInfo>> _getStaffSnapshot(
    Database db,
  ) async {
    final cached = _staffSnapshot;
    if (cached != null) return cached;
    final records = await _staffStore.find(db);
    final map = <String, SeatStatusStaffInfo>{};
    for (final record in records) {
      final raw = record.value;
      if (raw is! Map) continue;
      final key = record.key.trim().toUpperCase();
      if (!_isMeaningfulInitial(key)) continue;
      try {
        map[key] = SeatStatusStaffInfo.fromJson(raw.cast<String, dynamic>());
      } catch (_) {}
    }
    _staffSnapshot = map;
    return map;
  }

  Future<Map<int, SeatStatusDetailsResponse>>
  _fetchAllSectionsDetailsBundle() async {
    try {
      final body = await _fetchText(_allSectionsDetailsUrl);
      final parsed = await compute(_parseDetailsBundleResponseFromBody, body);
      await _saveDetailsIfAny(parsed);
      return parsed;
    } catch (_) {
      return const <int, SeatStatusDetailsResponse>{};
    }
  }

  Future<Map<int, SeatStatusDetailsResponse>> _fetchSectionDetailsDirect(
    List<int> sectionIds, {
    int concurrency = 8,
  }) async {
    final result = <int, SeatStatusDetailsResponse>{};
    var index = 0;
    while (index < sectionIds.length) {
      final end = (index + concurrency > sectionIds.length)
          ? sectionIds.length
          : index + concurrency;
      final batch = sectionIds.sublist(index, end);
      await Future.wait(
        batch.map((sectionId) async {
          try {
            final raw = await _fetchJson(_sectionDetailsUrl(sectionId));
            if (raw is! Map) return;
            result[sectionId] = SeatStatusDetailsResponse.fromJson(
              raw.cast<String, dynamic>(),
            );
          } catch (_) {}
        }),
      );
      index = end;
    }
    return result;
  }

  Future<dynamic> _fetchJson(String url) async {
    final response = await _client.publicGet(
      url,
      acceptedStatusCodes: const <int>{200},
    );
    return jsonDecode(response.body);
  }

  Future<String> _fetchText(String url) async {
    final response = await _client.publicGet(
      url,
      acceptedStatusCodes: const <int>{200},
    );
    return response.body;
  }

  Future<void> _saveDetailsIfAny(
    Map<int, SeatStatusDetailsResponse> details,
  ) async {
    if (details.isEmpty) return;
    await saveDetailsCache(details);
  }

  List<String> _normalizedInitials(Iterable<String> initials) {
    final normalized = initials
        .map((value) => value.trim().toUpperCase())
        .where(_isMeaningfulInitial)
        .toSet()
        .toList();
    normalized.sort((a, b) => a.compareTo(b));
    return normalized;
  }

  Set<String> _collectFacultyInitials(
    Iterable<SeatStatusDetailsResponse> detailsValues,
  ) {
    final initials = <String>{};
    for (final details in detailsValues) {
      final main = details.section.faculties;
      if (_isMeaningfulInitial(main)) {
        initials.add(main.trim().toUpperCase());
      }
      final child = details.childSection?.faculties ?? '';
      if (_isMeaningfulInitial(child)) {
        initials.add(child.trim().toUpperCase());
      }
    }
    return initials;
  }
}

bool _jsonDeepEqual(Map<String, dynamic> a, Map<String, dynamic> b) {
  return jsonEncode(a) == jsonEncode(b);
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

Map<int, SeatStatusDetailsResponse> _parseDetailsBundleResponse(dynamic raw) {
  if (raw is Map) {
    final mapped = raw.map((key, value) => MapEntry('$key', value));
    final direct = _parseCachedDetailsFromMap(mapped);
    if (direct.isNotEmpty) return direct;

    for (final key in SeatStatusService._detailsWrapperKeys) {
      final nested = _parseDetailsBundleResponse(raw[key]);
      if (nested.isNotEmpty) return nested;
    }
  }

  if (raw is List) {
    final result = <int, SeatStatusDetailsResponse>{};
    for (final item in raw.whereType<Map>()) {
      final map = item.cast<String, dynamic>();
      final details = SeatStatusDetailsResponse.fromJson(map);
      final sectionId = details.section.sectionId;
      if (sectionId <= 0) continue;
      result[sectionId] = details;
    }
    return result;
  }

  return const <int, SeatStatusDetailsResponse>{};
}

Map<int, SeatStatusDetailsResponse> _parseDetailsBundleResponseFromBody(
  String body,
) {
  return _parseDetailsBundleResponse(jsonDecode(body));
}

Map<int, int> _parseSeatMapResponse(dynamic raw) {
  final result = <int, int>{};

  void addEntry(int? sectionId, int? remaining) {
    if (sectionId == null || sectionId <= 0) return;
    result[sectionId] = remaining ?? 0;
  }

  int? remainingFromMap(Map<dynamic, dynamic> map) {
    final directKeys = <String>[
      'remaining',
      'available',
      'availableSeat',
      'remainingSeat',
      'seat',
      'value',
    ];
    for (final key in directKeys) {
      final value = int.tryParse('${map[key] ?? ''}');
      if (value != null) return value;
    }
    final capacity = int.tryParse('${map['capacity'] ?? ''}');
    final consumed = int.tryParse(
      '${map['consumedSeat'] ?? map['consumed'] ?? ''}',
    );
    if (capacity != null && consumed != null) {
      return capacity - consumed;
    }
    return null;
  }

  Map<int, int> parseAny(dynamic value) {
    if (value is Map) {
      final direct = <int, int>{};
      var allKeyedInts = true;
      for (final entry in value.entries) {
        final key = int.tryParse('${entry.key}');
        final val = int.tryParse('${entry.value}');
        if (key == null || val == null) {
          allKeyedInts = false;
          break;
        }
        direct[key] = val;
      }
      if (allKeyedInts && direct.isNotEmpty) return direct;

      for (final entry in value.entries) {
        final nestedMap = entry.value;
        if (nestedMap is Map) {
          addEntry(
            int.tryParse('${nestedMap['sectionId'] ?? entry.key}'),
            remainingFromMap(nestedMap),
          );
        }
      }
      if (result.isNotEmpty) return result;

      for (final key in SeatStatusService._seatMapWrapperKeys) {
        final nested = parseAny(value[key]);
        if (nested.isNotEmpty) return nested;
      }
    }

    if (value is List) {
      for (final item in value.whereType<Map>()) {
        addEntry(
          int.tryParse('${item['sectionId'] ?? item['id'] ?? ''}'),
          remainingFromMap(item),
        );
      }
      if (result.isNotEmpty) return result;
    }

    return const <int, int>{};
  }

  final parsed = parseAny(raw);
  if (parsed.isNotEmpty) {
    return parsed;
  }
  return result;
}

class SeatStatusStaffInfo {
  const SeatStatusStaffInfo({
    required this.staffId,
    required this.shortName,
    required this.staffName,
    required this.email,
    required this.departmentId,
    required this.designationId,
  });

  final int staffId;
  final String shortName;
  final String staffName;
  final String email;
  final int? departmentId;
  final int? designationId;

  factory SeatStatusStaffInfo.fromJson(Map<String, dynamic> json) {
    return SeatStatusStaffInfo(
      staffId: int.tryParse('${json['staffId'] ?? 0}') ?? 0,
      shortName: '${json['shortName'] ?? ''}'.trim(),
      staffName: '${json['staffName'] ?? ''}'.trim(),
      email: '${json['email'] ?? ''}'.trim(),
      departmentId: int.tryParse('${json['departmentId'] ?? ''}'),
      designationId: int.tryParse('${json['designationId'] ?? ''}'),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'staffId': staffId,
      'shortName': shortName,
      'staffName': staffName,
      'email': email,
      'departmentId': departmentId,
      'designationId': designationId,
    };
  }
}

class SeatAlertConfig {
  const SeatAlertConfig({
    required this.sectionId,
    this.notifyOnAvailable = false,
    this.availableOneTime = true,
    this.thresholdSeats,
    this.thresholdOneTime = true,
    this.notifyOnAnyChange = false,
    this.changeCooldownMinutes = 0,
    this.lastChangeNotifiedAtMs,
  });

  final int sectionId;
  final bool notifyOnAvailable;
  final bool availableOneTime;
  final int? thresholdSeats;
  final bool thresholdOneTime;
  final bool notifyOnAnyChange;
  final int changeCooldownMinutes;
  final int? lastChangeNotifiedAtMs;

  bool get hasAnyRule =>
      notifyOnAvailable || thresholdSeats != null || notifyOnAnyChange;

  factory SeatAlertConfig.fromJson(int sectionId, Map<String, dynamic> json) {
    return SeatAlertConfig(
      sectionId: sectionId,
      notifyOnAvailable: json['notifyOnAvailable'] == true,
      availableOneTime: json['availableOneTime'] != false,
      thresholdSeats: int.tryParse('${json['thresholdSeats'] ?? ''}'),
      thresholdOneTime: json['thresholdOneTime'] != false,
      notifyOnAnyChange: json['notifyOnAnyChange'] == true,
      changeCooldownMinutes:
          int.tryParse('${json['changeCooldownMinutes'] ?? ''}') ?? 0,
      lastChangeNotifiedAtMs: int.tryParse(
        '${json['lastChangeNotifiedAtMs'] ?? ''}',
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'notifyOnAvailable': notifyOnAvailable,
      'availableOneTime': availableOneTime,
      'thresholdSeats': thresholdSeats,
      'thresholdOneTime': thresholdOneTime,
      'notifyOnAnyChange': notifyOnAnyChange,
      'changeCooldownMinutes': changeCooldownMinutes,
      'lastChangeNotifiedAtMs': lastChangeNotifiedAtMs,
    };
  }

  SeatAlertConfig copyWith({
    bool? notifyOnAvailable,
    bool? availableOneTime,
    Object? thresholdSeats = _seatAlertSentinel,
    bool? thresholdOneTime,
    bool? notifyOnAnyChange,
    int? changeCooldownMinutes,
    Object? lastChangeNotifiedAtMs = _seatAlertSentinel,
  }) {
    return SeatAlertConfig(
      sectionId: sectionId,
      notifyOnAvailable: notifyOnAvailable ?? this.notifyOnAvailable,
      availableOneTime: availableOneTime ?? this.availableOneTime,
      thresholdSeats: identical(thresholdSeats, _seatAlertSentinel)
          ? this.thresholdSeats
          : thresholdSeats as int?,
      thresholdOneTime: thresholdOneTime ?? this.thresholdOneTime,
      notifyOnAnyChange: notifyOnAnyChange ?? this.notifyOnAnyChange,
      changeCooldownMinutes:
          changeCooldownMinutes ?? this.changeCooldownMinutes,
      lastChangeNotifiedAtMs:
          identical(lastChangeNotifiedAtMs, _seatAlertSentinel)
          ? this.lastChangeNotifiedAtMs
          : lastChangeNotifiedAtMs as int?,
    );
  }
}

const Object _seatAlertSentinel = Object();
