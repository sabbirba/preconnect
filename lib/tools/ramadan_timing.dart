import 'dart:convert';

import 'package:preconnect/tools/http_service.dart';

import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/tools/time_utils.dart';

class RamadanStatus {
  const RamadanStatus({
    required this.isRamadan,
    this.ramadanDay,
    this.sehriEndsAt,
    this.iftarAt,
  });

  final bool isRamadan;
  final int? ramadanDay;
  final String? sehriEndsAt;
  final String? iftarAt;

  Map<String, dynamic> toCacheJson() {
    return <String, dynamic>{
      'isRamadan': isRamadan,
      'ramadanDay': ramadanDay,
      'sehriEndsAt': sehriEndsAt,
      'iftarAt': iftarAt,
    };
  }

  static RamadanStatus fromCache(dynamic json) {
    if (json is! Map) {
      return const RamadanStatus(isRamadan: false);
    }
    final payload = Map<String, dynamic>.from(json);
    return RamadanTiming._parseStatus(payload) ??
        const RamadanStatus(isRamadan: false);
  }
}

class RamadanTiming {
  RamadanTiming._();

  static List<String> get _statusUrls => <String>[
    '${ApiConfig.publicJsonBase}/ramadan.json',
    '${ApiConfig.publicJsonBase}/data/ramadan.json',
    '${ApiConfig.seatStatusProxyBase}/ramadan',
  ];
  static const Duration _requestTimeout = Duration(seconds: 2);
  static final ({DateTime start, DateTime end}) _knownRamadanWindow2026 = (
    start: DateTime(2026, 2, 18),
    end: DateTime(2026, 3, 19),
  );

  static Future<RamadanStatus>? _inflight;

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
    if (_inflight != null) {
      return _inflight!;
    }

    _inflight = _refreshRamadanStatus();
    return _inflight!;
  }

  static Future<RamadanStatus> _refreshRamadanStatus() async {
    try {
      final result = await _fetchRamadanStatus();
      return result.fromNetwork ? result.value : _fallbackOfflineStatus();
    } finally {
      _inflight = null;
    }
  }

  static Future<({RamadanStatus value, bool fromNetwork})>
  _fetchRamadanStatus() async {
    final fallbackPayload = await _fetchPayload();
    final parsedFallback = _parseStatus(fallbackPayload);
    if (parsedFallback != null) {
      return (value: parsedFallback, fromNetwork: true);
    }

    return (value: const RamadanStatus(isRamadan: false), fromNetwork: false);
  }

  static RamadanStatus _fallbackOfflineStatus() {
    if (_isWithinKnownRamadanWindow(DateTime.now())) {
      final window = _knownRamadanWindow2026;
      final day = DateTime.now().difference(window.start).inDays + 1;
      return RamadanStatus(
        isRamadan: true,
        ramadanDay: day > 0 ? day : null,
        sehriEndsAt: null,
        iftarAt: null,
      );
    }

    return const RamadanStatus(isRamadan: false);
  }

  static Future<Map<String, dynamic>?> _fetchPayload() async {
    for (final url in _statusUrls) {
      try {
        final response = await HttpService.client
            .get(Uri.parse(url), headers: const {'Accept': 'application/json'})
            .timeout(_requestTimeout);

        if (response.statusCode != 200 || response.body.trim().isEmpty) {
          continue;
        }

        final payload = jsonDecode(response.body);
        if (payload is! Map<String, dynamic>) {
          continue;
        }

        return payload;
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  static RamadanStatus? _parseStatus(Map<String, dynamic>? payload) {
    if (payload == null) return null;

    final isRamadanValue = payload['isRamadan'];
    final isRamadan = isRamadanValue is bool ? isRamadanValue : false;
    final ramadanDay = switch (payload['ramadanDay']) {
      int value => value,
      num value => value.toInt(),
      _ => null,
    };
    final sehriEndsAt = _asTimeString(payload['sehriEndsAt']);
    final iftarAt = _asTimeString(payload['iftarAt']);

    return RamadanStatus(
      isRamadan: isRamadan,
      ramadanDay: ramadanDay,
      sehriEndsAt: sehriEndsAt,
      iftarAt: iftarAt,
    );
  }

  static String? _asTimeString(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    return trimmed;
  }

  static bool _isWithinKnownRamadanWindow(DateTime date) {
    final window = _knownRamadanWindow2026;
    final start = DateTime(
      window.start.year,
      window.start.month,
      window.start.day,
    );
    final end = DateTime(
      window.end.year,
      window.end.month,
      window.end.day,
      23,
      59,
      59,
    );
    return !date.isBefore(start) && !date.isAfter(end);
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
