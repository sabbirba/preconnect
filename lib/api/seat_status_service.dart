import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:preconnect/api/api_client.dart';
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/model/seat_status_info.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SeatStatusService {
  SeatStatusService._internal();

  static final SeatStatusService _instance = SeatStatusService._internal();
  factory SeatStatusService() => _instance;

  final ApiClient _client = ApiClient();
  static const String _detailsCacheKey = 'seat_status_details_cache_v1';
  static const String _detailsCacheTsKey = 'seat_status_details_cache_ts_v1';
  static const String _seatMapCacheKey = 'seat_status_map_cache_v1';
  static const String _seatMapCacheTsKey = 'seat_status_map_cache_ts_v1';

  Future<Map<int, int>> fetchSeatStatusMap() async {
    final response = await _client.authenticatedGet(ApiConfig.seatStatusUrl);
    return compute(_parseSeatMapFromBody, response.body);
  }

  Future<Map<int, int>> loadCachedSeatMap({
    Duration maxAge = const Duration(hours: 1),
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ts = prefs.getInt(_seatMapCacheTsKey);
      if (ts == null) return const <int, int>{};
      final age = DateTime.now().difference(
        DateTime.fromMillisecondsSinceEpoch(ts),
      );
      if (age > maxAge) return const <int, int>{};
      final raw = prefs.getString(_seatMapCacheKey);
      if (raw == null || raw.trim().isEmpty) return const <int, int>{};
      return compute(_parseSeatMapFromBody, raw);
    } catch (_) {
      return const <int, int>{};
    }
  }

  Future<SeatStatusDetailsResponse?> fetchSectionDetails(int sectionId) async {
    final response = await _client.authenticatedGet(
      ApiConfig.sectionDetailsUrl(sectionId),
    );
    return compute(_parseDetailsFromBody, response.body);
  }

  Future<Map<int, SeatStatusDetailsResponse>> loadCachedDetails({
    Duration maxAge = const Duration(hours: 1),
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ts = prefs.getInt(_detailsCacheTsKey);
      if (ts == null) return const <int, SeatStatusDetailsResponse>{};
      final age = DateTime.now().difference(
        DateTime.fromMillisecondsSinceEpoch(ts),
      );
      if (age > maxAge) return const <int, SeatStatusDetailsResponse>{};
      final raw = prefs.getString(_detailsCacheKey);
      if (raw == null || raw.trim().isEmpty) {
        return const <int, SeatStatusDetailsResponse>{};
      }
      return compute(_parseCachedDetailsFromRaw, raw);
    } catch (_) {
      return const <int, SeatStatusDetailsResponse>{};
    }
  }

  Future<void> saveDetailsCache(
    Map<int, SeatStatusDetailsResponse> cache,
  ) async {
    if (cache.isEmpty) return;
    try {
      final encoded = jsonEncode(
        cache.map((k, v) => MapEntry(k.toString(), v.toJson())),
      );
      final prefs = await SharedPreferences.getInstance();
      final existing = prefs.getString(_detailsCacheKey);
      if (existing == encoded) return;
      await prefs.setString(_detailsCacheKey, encoded);
      await prefs.setInt(
        _detailsCacheTsKey,
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (_) {}
  }

  Future<void> saveSeatMapCacheIfChanged(Map<int, int> seatMap) async {
    if (seatMap.isEmpty) return;
    try {
      final encoded = jsonEncode(
        seatMap.map((k, v) => MapEntry(k.toString(), v)),
      );
      final prefs = await SharedPreferences.getInstance();
      final existing = prefs.getString(_seatMapCacheKey);
      if (existing == encoded) return;
      await prefs.setString(_seatMapCacheKey, encoded);
      await prefs.setInt(
        _seatMapCacheTsKey,
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (_) {}
  }
}

Map<int, int> _parseSeatMapFromBody(String body) {
  final decoded = jsonDecode(body);
  if (decoded is! Map) return const <int, int>{};
  final result = <int, int>{};
  for (final entry in decoded.entries) {
    final key = int.tryParse('${entry.key}');
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

Map<int, SeatStatusDetailsResponse> _parseCachedDetailsFromRaw(String raw) {
  final decoded = jsonDecode(raw);
  if (decoded is! Map) return const <int, SeatStatusDetailsResponse>{};
  final result = <int, SeatStatusDetailsResponse>{};
  for (final entry in decoded.entries) {
    final key = int.tryParse('${entry.key}');
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
