import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:preconnect/api/api_client.dart';
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/model/seat_status_info.dart';
import 'package:preconnect/tools/app_storage.dart';

class SeatStatusService {
  SeatStatusService._internal();
  static final SeatStatusService _instance = SeatStatusService._internal();
  factory SeatStatusService() => _instance;

  static const String _detailsKey = 'seat_status_details_json_v1';
  static const String _detailsTsKey = 'seat_status_details_ts_v1';
  static const String _freeLabsKey = 'free_labs_slots_v1';
  static const String _freeLabsDateKey = 'free_labs_slots_date_v1';

  final ApiClient _client = ApiClient();
  Map<int, SeatStatusDetailsResponse>? _detailsSnapshot;
  int? _detailsSnapshotTs;
  final Map<String, SeatStatusStaffInfo> _staffInfoByInitialCache =
      <String, SeatStatusStaffInfo>{};
  final Map<String, Future<SeatStatusStaffInfo?>> _staffInfoInFlight =
      <String, Future<SeatStatusStaffInfo?>>{};
  final ValueNotifier<bool> isSavingDetailsCache = ValueNotifier<bool>(false);

  String get seatStatusStreamUrl =>
      '${ApiConfig.seatStatusProxyBase}/seat-status/stream';

  Future<Map<int, SeatStatusDetailsResponse>> loadCachedDetails({
    Duration maxAge = const Duration(hours: 1),
  }) async {
    try {
      final ts = await AppStorage.instance.getInt(_detailsTsKey);
      final raw = await AppStorage.instance.getString(_detailsKey);
      if (ts == null || raw == null || raw.trim().isEmpty) {
        return const <int, SeatStatusDetailsResponse>{};
      }
      final age = DateTime.now().difference(
        DateTime.fromMillisecondsSinceEpoch(ts),
      );
      if (age > maxAge) return const <int, SeatStatusDetailsResponse>{};
      if (_detailsSnapshotTs == ts && _detailsSnapshot != null) {
        return Map<int, SeatStatusDetailsResponse>.from(_detailsSnapshot!);
      }
      final decoded = jsonDecode(raw);
      final snapshot = _parseCachedDetailsFromMap(decoded);
      _detailsSnapshotTs = ts;
      _detailsSnapshot = Map<int, SeatStatusDetailsResponse>.from(snapshot);
      return snapshot;
    } catch (e) {
      return const <int, SeatStatusDetailsResponse>{};
    }
  }

  Future<void> saveDetailsCache(
    Map<int, SeatStatusDetailsResponse> detailsBySection,
  ) async {
    if (detailsBySection.isEmpty) return;
    isSavingDetailsCache.value = true;
    try {
      final payload = detailsBySection.map(
        (key, value) => MapEntry(key.toString(), value.toJson()),
      );
      await AppStorage.instance.setString(_detailsKey, jsonEncode(payload));
      await AppStorage.instance.setInt(
        _detailsTsKey,
        DateTime.now().millisecondsSinceEpoch,
      );
      _detailsSnapshot = null;
      _detailsSnapshotTs = null;
    } finally {
      isSavingDetailsCache.value = false;
    }
  }

  Future<List<Map<String, dynamic>>> loadCachedFreeLabsSlots({
    required String dateKey,
  }) async {
    try {
      final cachedDate = await AppStorage.instance.getString(_freeLabsDateKey);
      final raw = await AppStorage.instance.getString(_freeLabsKey);
      if (cachedDate != dateKey || raw == null || raw.trim().isEmpty) {
        return const <Map<String, dynamic>>[];
      }
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const <Map<String, dynamic>>[];
      return decoded
          .whereType<Map>()
          .map((item) => item.cast<String, dynamic>())
          .toList();
    } catch (e) {
      return const <Map<String, dynamic>>[];
    }
  }

  Future<void> saveFreeLabsSlotsCacheIfChanged({
    required String dateKey,
    required List<Map<String, dynamic>> slots,
  }) async {
    await AppStorage.instance.setString(_freeLabsKey, jsonEncode(slots));
    await AppStorage.instance.setString(_freeLabsDateKey, dateKey);
  }

  Future<Map<int, SeatStatusDetailsResponse>>
  fetchAllSectionsDetailsFromApi() async {
    final raw = await _fetchJson(
      '${ApiConfig.seatStatusProxyBase}/seat-status',
    );
    final parsed = _parseSeatMapResponse(raw);
    if (parsed.isEmpty) return const <int, SeatStatusDetailsResponse>{};
    final details = await _fetchSectionDetailsDirect(parsed.keys.toList());
    if (details.isNotEmpty) {
      await saveDetailsCache(details);
    }
    return details;
  }

  Future<void> preloadSeatStatusCache({int detailConcurrency = 8}) async {}

  Future<void> clearAll() async {
    await AppStorage.instance.remove(_detailsKey);
    await AppStorage.instance.remove(_detailsTsKey);
    await AppStorage.instance.remove(_freeLabsKey);
    await AppStorage.instance.remove(_freeLabsDateKey);
    _detailsSnapshot = null;
    _detailsSnapshotTs = null;
    _staffInfoByInitialCache.clear();
  }

  Future<SeatStatusStaffInfo?> getStaffInfoForInitial(String initial) async {
    final key = initial.trim().toUpperCase();
    if (key.isEmpty) return null;
    final cached = _staffInfoByInitialCache[key];
    if (cached != null) return cached;
    final inFlight = _staffInfoInFlight[key];
    if (inFlight != null) return inFlight;
    final request = _fetchStaffInfoForInitial(key);
    _staffInfoInFlight[key] = request;
    try {
      return await request;
    } finally {
      _staffInfoInFlight.remove(key);
    }
  }

  Future<SeatStatusStaffInfo?> _fetchStaffInfoForInitial(String initial) async {
    try {
      final response = await _client.publicGet(
        '${ApiConfig.seatStatusProxyBase}/staff/${Uri.encodeComponent(initial)}',
      );
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        final info = SeatStatusStaffInfo.fromJson(decoded);
        _staffInfoByInitialCache[initial] = info;
        return info;
      }
    } catch (_) {}
    return null;
  }

  Future<Map<String, SeatStatusStaffInfo>> resolveStaffInfoByInitials(
    Iterable<String> initials, {
    int concurrency = 6,
  }) async {
    final requested = initials
        .map((value) => value.trim().toUpperCase())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList();
    final output = <String, SeatStatusStaffInfo>{};
    for (final key in requested) {
      final info = await getStaffInfoForInitial(key);
      if (info != null) output[key] = info;
    }
    return output;
  }

  Future<dynamic> _fetchJson(String url) async {
    final response = await _client.publicGet(
      url,
      acceptedStatusCodes: const <int>{200},
    );
    try {
      return jsonDecode(response.body);
    } catch (e) {
      throw FormatException('Invalid JSON response from $url: $e');
    }
  }

  Map<int, int> _parseSeatMapResponse(dynamic raw) {
    if (raw is! Map) return const <int, int>{};
    final data = raw['data'];
    if (data is! List) return const <int, int>{};
    final result = <int, int>{};
    for (final item in data.whereType<Map>()) {
      final map = item.cast<String, dynamic>();
      final sectionId = int.tryParse('${map['sectionId'] ?? ''}');
      if (sectionId == null) continue;
      result[sectionId] = sectionId;
    }
    return result;
  }

  Future<Map<int, SeatStatusDetailsResponse>> _fetchSectionDetailsDirect(
    List<int> sectionIds,
  ) async {
    final result = <int, SeatStatusDetailsResponse>{};
    for (final sectionId in sectionIds) {
      try {
        final raw = await _fetchJson(
          '${ApiConfig.seatStatusProxyBase}/sections/$sectionId/details',
        );
        if (raw is Map<String, dynamic>) {
          result[sectionId] = SeatStatusDetailsResponse.fromJson(raw);
        }
      } catch (_) {}
    }
    return result;
  }
}

Map<int, SeatStatusDetailsResponse> _parseCachedDetailsFromMap(dynamic raw) {
  if (raw is! Map) return const <int, SeatStatusDetailsResponse>{};
  final out = <int, SeatStatusDetailsResponse>{};
  for (final entry in raw.entries) {
    final id = int.tryParse('${entry.key}');
    if (id == null || entry.value is! Map) continue;
    try {
      out[id] = SeatStatusDetailsResponse.fromJson(
        Map<String, dynamic>.from(entry.value as Map),
      );
    } catch (_) {}
  }
  return out;
}
