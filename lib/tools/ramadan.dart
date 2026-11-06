import 'package:preconnect/api/api_client.dart';
import 'package:preconnect/tools/preload_cache.dart';
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

  static const Duration _statusCacheDuration = Duration(minutes: 5);
  static final ({DateTime start, DateTime end}) _knownRamadanWindow2026 = (
    start: DateTime(2026, 2, 18),
    end: DateTime(2026, 3, 19),
  );

  static final PreloadCache<RamadanStatus> _refresh =
      PreloadCache<RamadanStatus>();

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
    return _refresh.share(
      () => _refreshRamadanStatus(forceRefresh: forceRefresh),
    );
  }

  static Future<RamadanStatus> _refreshRamadanStatus({
    required bool forceRefresh,
  }) async {
    final payload = await ApiClient().tryPublicJson(
      ApiConfig.ramadanStatusUrl,
      cacheDuration: forceRefresh ? Duration.zero : _statusCacheDuration,
    );
    final status = payload is Map<String, dynamic>
        ? _parseStatus(payload)
        : null;
    return status ?? _fallbackOfflineStatus();
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

  static RamadanStatus? _parseStatus(Map<String, dynamic>? payload) {
    if (payload == null) return null;

    final isRamadanValue = payload['isRamadan'];
    final isRamadan = isRamadanValue is bool ? isRamadanValue : false;
    final ramadanDay = switch (payload['ramadanDay']) {
      final int value => value,
      final num value => value.toInt(),
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

    final startMinutes = AppTime.toMinutes(startTime);
    final endMinutes = AppTime.toMinutes(endTime);
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
    return AppTime.toMinutes(adjusted.startTime) ?? 0;
  }

  static int effectiveEndMinutes(
    String startTime,
    String endTime, {
    required bool isRamadan,
  }) {
    final adjusted = adjustRange(startTime, endTime, isRamadan: isRamadan);
    return AppTime.toMinutes(adjusted.endTime) ?? 0;
  }

  static String _minutesTo24h(int totalMinutes) {
    final hour = (totalMinutes ~/ 60).toString().padLeft(2, '0');
    final minute = (totalMinutes % 60).toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}
