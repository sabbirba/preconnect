import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

typedef HolidayItem = ({String date, String name});

class HolidayStatus {
  const HolidayStatus({
    required this.isTodayHoliday,
    required this.todayHolidayNames,
    required this.nextHolidaysThisYear,
  });

  static const HolidayStatus empty = HolidayStatus(
    isTodayHoliday: false,
    todayHolidayNames: <String>[],
    nextHolidaysThisYear: <HolidayItem>[],
  );

  final bool isTodayHoliday;
  final List<String> todayHolidayNames;
  final List<HolidayItem> nextHolidaysThisYear;

  String get displayNames => todayHolidayNames.isEmpty
      ? 'Today is a holiday.'
      : todayHolidayNames.join(' • ');

  Map<String, dynamic> toCacheJson() {
    return <String, dynamic>{
      'isTodayHoliday': isTodayHoliday,
      'todayHolidayNames': todayHolidayNames,
      'nextHolidaysThisYear': nextHolidaysThisYear
          .map((item) => {'date': item.date, 'name': item.name})
          .toList(),
    };
  }

  static HolidayStatus fromApi(Map<String, dynamic> json) {
    return HolidayStatus(
      isTodayHoliday: json['isTodayHoliday'] == true,
      todayHolidayNames: _namesFromAny(json['todayHolidays']),
      nextHolidaysThisYear: _itemsFromAny(json['nextHolidaysThisYear']),
    );
  }

  static HolidayStatus fromCache(dynamic json) {
    if (json is! Map) return HolidayStatus.empty;
    final map = Map<String, dynamic>.from(json);
    return HolidayStatus(
      isTodayHoliday: map['isTodayHoliday'] == true,
      todayHolidayNames: _namesFromAny(map['todayHolidayNames']),
      nextHolidaysThisYear: _itemsFromAny(map['nextHolidaysThisYear']),
    );
  }

  static List<String> _namesFromAny(dynamic source) {
    if (source is! List) return const <String>[];

    final seen = <String>{};
    final names = <String>[];
    for (final item in source) {
      final raw = item is String
          ? item
          : (item is Map ? Map<String, dynamic>.from(item)['name'] : null);
      final name = _clean(raw);
      if (name == null || !seen.add(name)) continue;
      names.add(name);
    }
    return names;
  }

  static List<HolidayItem> _itemsFromAny(dynamic source) {
    if (source is! List) return const <HolidayItem>[];

    final seen = <String>{};
    final items = <HolidayItem>[];
    for (final item in source) {
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);
      final date = _clean(map['date']);
      final name = _clean(map['name']);
      if (date == null || name == null) continue;
      final key = '$date|$name';
      if (!seen.add(key)) continue;
      items.add((date: date, name: name));
    }
    return items;
  }

  static String? _clean(dynamic value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

class HolidayTiming {
  HolidayTiming._();

  static const String _statusUrl = 'https://preconnect.app/api/holiday';
  static const Duration _requestTimeout = Duration(seconds: 3);
  static const Duration _cacheTtl = Duration(hours: 6);
  static const String _prefsStatusKey = 'holiday_status_json';
  static const String _prefsLastCheckKey = 'holiday_last_check_epoch_ms';

  static DateTime? _lastCheckAt;
  static HolidayStatus? _cachedStatus;
  static bool _cacheLoaded = false;
  static Future<void>? _cacheLoadInflight;
  static Future<HolidayStatus>? _inflight;

  static Future<HolidayStatus> getTodayStatus({
    bool forceRefresh = false,
  }) async {
    await _ensureCacheLoaded();

    final now = DateTime.now();
    final hasFreshCache =
        !forceRefresh &&
        _cachedStatus != null &&
        _lastCheckAt != null &&
        _sameDate(now, _lastCheckAt!) &&
        now.difference(_lastCheckAt!) <= _cacheTtl;

    if (hasFreshCache) return _cachedStatus!;
    if (_inflight != null) return _inflight!;

    _inflight = _refreshStatus(now);
    return _inflight!;
  }

  static Future<List<HolidayItem>> getNextHolidaysThisYear({
    bool forceRefresh = false,
  }) async {
    final status = await getTodayStatus(forceRefresh: forceRefresh);
    return status.nextHolidaysThisYear;
  }

  static Future<HolidayStatus> _refreshStatus(DateTime now) async {
    try {
      final result = await _fetchTodayStatus();
      final value = result.fromNetwork
          ? result.value
          : _fallbackOfflineStatus(now);
      _cachedStatus = value;
      if (result.fromNetwork) {
        _lastCheckAt = now;
        await _persistCache();
      }
      return value;
    } finally {
      _inflight = null;
    }
  }

  static Future<void> _ensureCacheLoaded() async {
    if (_cacheLoaded) return;
    if (_cacheLoadInflight != null) return _cacheLoadInflight!;

    _cacheLoadInflight = _loadCacheFromPrefs();
    try {
      await _cacheLoadInflight!;
    } finally {
      _cacheLoadInflight = null;
    }
  }

  static Future<void> _loadCacheFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawStatus = prefs.getString(_prefsStatusKey);
      final rawEpoch = prefs.getInt(_prefsLastCheckKey);

      _cachedStatus = rawStatus == null
          ? HolidayStatus.empty
          : HolidayStatus.fromCache(jsonDecode(rawStatus));
      _lastCheckAt = rawEpoch == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(rawEpoch);
    } catch (_) {
      _cachedStatus = HolidayStatus.empty;
      _lastCheckAt = null;
    } finally {
      _cacheLoaded = true;
    }
  }

  static Future<void> _persistCache() async {
    final status = _cachedStatus;
    final lastCheckAt = _lastCheckAt;
    if (status == null || lastCheckAt == null) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsStatusKey, jsonEncode(status.toCacheJson()));
      await prefs.setInt(
        _prefsLastCheckKey,
        lastCheckAt.millisecondsSinceEpoch,
      );
    } catch (_) {}
  }

  static Future<({HolidayStatus value, bool fromNetwork})>
  _fetchTodayStatus() async {
    try {
      final response = await http
          .get(
            Uri.parse(_statusUrl),
            headers: const {'Accept': 'application/json'},
          )
          .timeout(_requestTimeout);

      if (response.statusCode != 200 || response.body.trim().isEmpty) {
        return (
          value: _cachedStatus ?? HolidayStatus.empty,
          fromNetwork: false,
        );
      }

      final payload = jsonDecode(response.body);
      if (payload is! Map<String, dynamic>) {
        return (
          value: _cachedStatus ?? HolidayStatus.empty,
          fromNetwork: false,
        );
      }

      return (value: HolidayStatus.fromApi(payload), fromNetwork: true);
    } catch (_) {
      return (value: _cachedStatus ?? HolidayStatus.empty, fromNetwork: false);
    }
  }

  static HolidayStatus _fallbackOfflineStatus(DateTime now) {
    final cached = _cachedStatus ?? HolidayStatus.empty;
    if (_isCacheForDate(now)) return cached;

    final inferredToday = _inferTodayHolidayNames(
      now,
      cached.nextHolidaysThisYear,
    );
    return HolidayStatus(
      isTodayHoliday: inferredToday.isNotEmpty,
      todayHolidayNames: inferredToday,
      nextHolidaysThisYear: cached.nextHolidaysThisYear,
    );
  }

  static List<String> _inferTodayHolidayNames(
    DateTime now,
    List<HolidayItem> holidays,
  ) {
    final todayIso = _toIsoDate(now);
    final names = <String>[];
    for (final holiday in holidays) {
      if (holiday.date != todayIso || names.contains(holiday.name)) continue;
      names.add(holiday.name);
    }
    return names;
  }

  static bool _isCacheForDate(DateTime date) {
    final lastCheck = _lastCheckAt;
    return lastCheck != null && _sameDate(date, lastCheck);
  }

  static bool _sameDate(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  static String _toIsoDate(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }
}
