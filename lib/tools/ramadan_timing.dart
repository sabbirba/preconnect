import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:preconnect/tools/time_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RamadanStatus {
  const RamadanStatus({
    required this.isRamadan,
    this.ramadanDay,
    this.sehriEndsAt,
    this.iftarAt,
    this.prayerTimes = const {},
  });

  final bool isRamadan;
  final int? ramadanDay;
  final String? sehriEndsAt;
  final String? iftarAt;
  final Map<String, String> prayerTimes;
}

class RamadanTiming {
  RamadanTiming._();

  static const String _statusUrl = 'https://preconnect.app/api/ramadan';
  static const Duration _requestTimeout = Duration(seconds: 2);
  static const Duration _cacheTtl = Duration(hours: 6);
  static const String _prefsIsRamadanKey = 'ramadan_is_ramadan';
  static const String _prefsLastCheckKey = 'ramadan_last_check_epoch_ms';

  static DateTime? _lastCheckAt;
  static bool? _cachedIsRamadan;
  static RamadanStatus? _cachedStatus;
  static bool _cacheLoaded = false;
  static Future<void>? _cacheLoadInflight;
  static Future<RamadanStatus>? _inflight;

  // Based on BRACU Ramadan class and lab timing (2026).
  static const Map<String, (int start, int end)> _ramadanSlots = {
    '480-560': (480, 545),
    '570-650': (555, 620),
    '660-740': (630, 695),
    '750-830': (705, 770),
    '840-920': (780, 845),
    '930-1010': (855, 920),
    '1020-1100': (930, 995),
    '1110-1290': (960, 1080),
    '480-650': (480, 620),
    '570-740': (555, 695),
    '660-830': (630, 770),
    '750-920': (705, 845),
    '840-1010': (780, 920),
    '930-1100': (855, 995),
    '1020-1290': (930, 1080),
  };

  static Future<bool> isRamadan({bool forceRefresh = false}) async {
    final status = await getRamadanStatus(forceRefresh: forceRefresh);
    return status.isRamadan;
  }

  static Future<RamadanStatus> getRamadanStatus({
    bool forceRefresh = false,
  }) async {
    await _ensureCacheLoaded();

    final now = DateTime.now();
    final hasCompleteCachedStatus = _isCompleteStatus(_cachedStatus);
    final hasFreshCache =
        !forceRefresh &&
        hasCompleteCachedStatus &&
        _lastCheckAt != null &&
        now.difference(_lastCheckAt!) <= _cacheTtl;

    if (hasFreshCache) {
      return _cachedStatus!;
    }

    if (_inflight != null) {
      return _inflight!;
    }

    _inflight = _refreshRamadanStatus(now: now);
    return _inflight!;
  }

  static Future<RamadanStatus> _refreshRamadanStatus({
    required DateTime now,
  }) async {
    try {
      final result = await _fetchRamadanStatus();
      _cachedStatus = result.value;
      _cachedIsRamadan = result.value.isRamadan;
      if (result.fromNetwork) {
        _lastCheckAt = now;
        await _persistCache();
      }
      return result.value;
    } finally {
      _inflight = null;
    }
  }

  static Future<void> _ensureCacheLoaded() async {
    if (_cacheLoaded) return;
    if (_cacheLoadInflight != null) {
      await _cacheLoadInflight!;
      return;
    }

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
      final isRamadan = prefs.getBool(_prefsIsRamadanKey);
      final epochMs = prefs.getInt(_prefsLastCheckKey);

      _cachedIsRamadan = isRamadan;
      if (isRamadan != null) {
        _cachedStatus = RamadanStatus(isRamadan: isRamadan);
      }
      if (epochMs != null) {
        _lastCheckAt = DateTime.fromMillisecondsSinceEpoch(epochMs);
      }
    } catch (_) {
    } finally {
      _cacheLoaded = true;
    }
  }

  static Future<void> _persistCache() async {
    final cached = _cachedIsRamadan;
    final lastCheckAt = _lastCheckAt;
    if (cached == null || lastCheckAt == null) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsIsRamadanKey, cached);
      await prefs.setInt(
        _prefsLastCheckKey,
        lastCheckAt.millisecondsSinceEpoch,
      );
    } catch (_) {}
  }

  static Future<({RamadanStatus value, bool fromNetwork})>
  _fetchRamadanStatus() async {
    final fallbackPayload = await _fetchPayload();
    final parsedFallback = _parseStatus(fallbackPayload);
    if (parsedFallback != null) {
      return (value: parsedFallback, fromNetwork: true);
    }

    return (
      value:
          _cachedStatus ?? RamadanStatus(isRamadan: _cachedIsRamadan ?? false),
      fromNetwork: false,
    );
  }

  static Future<Map<String, dynamic>?> _fetchPayload() async {
    try {
      final response = await http
          .get(
            Uri.parse(_statusUrl),
            headers: const {'Accept': 'application/json'},
          )
          .timeout(_requestTimeout);

      if (response.statusCode != 200 || response.body.trim().isEmpty) {
        return null;
      }

      final payload = jsonDecode(response.body);
      if (payload is! Map<String, dynamic>) {
        return null;
      }

      return payload;
    } catch (_) {
      return null;
    }
  }

  static RamadanStatus? _parseStatus(Map<String, dynamic>? payload) {
    if (payload == null) return null;

    final isRamadanValue = payload['isRamadan'];
    final isRamadan = isRamadanValue is bool
        ? isRamadanValue
        : (_cachedIsRamadan ?? false);
    final ramadanDay = switch (payload['ramadanDay']) {
      int value => value,
      num value => value.toInt(),
      _ => null,
    };
    final sehriEndsAt = _asTimeString(payload['sehriEndsAt']);
    final iftarAt = _asTimeString(payload['iftarAt']);
    final prayerTimes = <String, String>{};
    final prayerTimesRaw = payload['prayerTimes'];
    if (prayerTimesRaw is Map) {
      for (final entry in prayerTimesRaw.entries) {
        final key = entry.key?.toString().trim() ?? '';
        final value = _asTimeString(entry.value);
        if (key.isEmpty || value == null) continue;
        prayerTimes[key] = value;
      }
    }

    return RamadanStatus(
      isRamadan: isRamadan,
      ramadanDay: ramadanDay,
      sehriEndsAt: sehriEndsAt,
      iftarAt: iftarAt,
      prayerTimes: prayerTimes,
    );
  }

  static String? _asTimeString(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    return trimmed;
  }

  static bool _isCompleteStatus(RamadanStatus? status) {
    if (status == null) return false;
    if (!status.isRamadan) return true;
    if (status.prayerTimes.isNotEmpty) return true;
    if (status.sehriEndsAt != null || status.iftarAt != null) return true;
    return false;
  }

  static ({String startTime, String endTime, bool adjusted}) adjustRange(
    String startTime,
    String endTime, {
    required bool isRamadan,
  }) {
    if (!isRamadan) {
      return (startTime: startTime, endTime: endTime, adjusted: false);
    }

    final startMinutes = BracuTime.toMinutes(startTime);
    final endMinutes = BracuTime.toMinutes(endTime);
    if (startMinutes == null || endMinutes == null) {
      return (startTime: startTime, endTime: endTime, adjusted: false);
    }

    final key = '$startMinutes-$endMinutes';
    final mapped = _ramadanSlots[key];
    if (mapped == null) {
      return (startTime: startTime, endTime: endTime, adjusted: false);
    }

    return (
      startTime: _minutesTo24h(mapped.$1),
      endTime: _minutesTo24h(mapped.$2),
      adjusted: true,
    );
  }

  static int effectiveStartMinutes(
    String startTime,
    String endTime, {
    required bool isRamadan,
  }) {
    final adjusted = adjustRange(startTime, endTime, isRamadan: isRamadan);
    return BracuTime.toMinutes(adjusted.startTime) ?? 0;
  }

  static int effectiveEndMinutes(
    String startTime,
    String endTime, {
    required bool isRamadan,
  }) {
    final adjusted = adjustRange(startTime, endTime, isRamadan: isRamadan);
    return BracuTime.toMinutes(adjusted.endTime) ?? 0;
  }

  static String _minutesTo24h(int totalMinutes) {
    final hour = (totalMinutes ~/ 60).toString().padLeft(2, '0');
    final minute = (totalMinutes % 60).toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}
