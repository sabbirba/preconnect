import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:preconnect/api/api_config.dart';

typedef HolidayItem = ({String startDate, String endDate, String label});

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

  String get displayNames => todayHolidayNames.join(' • ');

  Map<String, dynamic> toCacheJson() {
    return <String, dynamic>{
      'isTodayHoliday': isTodayHoliday,
      'todayHolidayNames': todayHolidayNames,
      'nextHolidaysThisYear': nextHolidaysThisYear
          .map(
            (item) => {
              'startDate': item.startDate,
              'endDate': item.endDate,
              'label': item.label,
            },
          )
          .toList(),
    };
  }

  static HolidayStatus fromApi(dynamic json) {
    if (json is List) {
      return _fromRawHolidayList(json);
    }
    if (json is! Map<String, dynamic>) {
      return HolidayStatus.empty;
    }
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
          : (item is Map
                ? (Map<String, dynamic>.from(item)['label'] ??
                      Map<String, dynamic>.from(item)['name'])
                : null);
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
      final startDate = _clean(map['startDate']) ?? _clean(map['date']);
      final endDate = _clean(map['endDate']) ?? startDate;
      final label = _clean(map['label']) ?? _clean(map['name']);
      if (startDate == null || endDate == null || label == null) continue;
      final key = '$startDate|$endDate|$label';
      if (!seen.add(key)) continue;
      items.add((startDate: startDate, endDate: endDate, label: label));
    }
    return items;
  }

  static String? _clean(dynamic value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static HolidayStatus _fromRawHolidayList(List<dynamic> source) {
    final todayIso = HolidayTiming._toIsoDate(DateTime.now());
    final nextHolidays = <HolidayItem>[];
    final todayHolidayNames = <String>[];
    final nextSeen = <String>{};
    final todaySeen = <String>{};

    for (final item in source) {
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);
      final startDate = _clean(map['startDate']);
      final endDate = _clean(map['endDate']);
      final label = _clean(map['label']);
      if (startDate == null || endDate == null || label == null) continue;
      final isCurrentOrUpcoming = endDate.compareTo(todayIso) >= 0;

      final nextKey = '$startDate|$endDate|$label';
      if (isCurrentOrUpcoming && nextSeen.add(nextKey)) {
        nextHolidays.add((
          startDate: startDate,
          endDate: endDate,
          label: label,
        ));
      }

      if (startDate.compareTo(todayIso) <= 0 &&
          endDate.compareTo(todayIso) >= 0) {
        if (todaySeen.add(label)) {
          todayHolidayNames.add(label);
        }
      }
    }

    nextHolidays.sort((a, b) => a.startDate.compareTo(b.startDate));
    return HolidayStatus(
      isTodayHoliday: todayHolidayNames.isNotEmpty,
      todayHolidayNames: todayHolidayNames,
      nextHolidaysThisYear: nextHolidays,
    );
  }
}

class HolidayTiming {
  HolidayTiming._();

  static List<String> get _statusUrls => <String>[
    '${ApiConfig.publicJsonBase}/holiday.json',
    '${ApiConfig.publicJsonBase}/data/holiday.json',
    '${ApiConfig.seatStatusProxyBase}/holiday',
  ];
  static const Duration _requestTimeout = Duration(seconds: 3);

  static Future<HolidayStatus>? _inflight;

  static Future<HolidayStatus> getTodayStatus({
    bool forceRefresh = false,
  }) async {
    if (_inflight != null) return _inflight!;

    _inflight = _refreshStatus();
    return _inflight!;
  }

  static Future<List<HolidayItem>> getNextHolidaysThisYear({
    bool forceRefresh = false,
  }) async {
    final status = await getTodayStatus(forceRefresh: forceRefresh);
    return status.nextHolidaysThisYear;
  }

  static Future<HolidayStatus> _refreshStatus() async {
    try {
      final result = await _fetchTodayStatus();
      return result.fromNetwork
          ? result.value
          : _fallbackOfflineStatus(DateTime.now());
    } finally {
      _inflight = null;
    }
  }

  static Future<({HolidayStatus value, bool fromNetwork})>
  _fetchTodayStatus() async {
    for (final url in _statusUrls) {
      try {
        final response = await http
            .get(Uri.parse(url), headers: const {'Accept': 'application/json'})
            .timeout(_requestTimeout);

        if (response.statusCode != 200 || response.body.trim().isEmpty) {
          continue;
        }

        final payload = jsonDecode(response.body);
        if (payload is! List && payload is! Map<String, dynamic>) {
          continue;
        }

        return (value: HolidayStatus.fromApi(payload), fromNetwork: true);
      } catch (_) {
        continue;
      }
    }
    return (value: HolidayStatus.empty, fromNetwork: false);
  }

  static HolidayStatus _fallbackOfflineStatus(DateTime now) {
    final inferredToday = _inferTodayHolidayNames(now, const <HolidayItem>[]);
    return HolidayStatus(
      isTodayHoliday: inferredToday.isNotEmpty,
      todayHolidayNames: inferredToday,
      nextHolidaysThisYear: const <HolidayItem>[],
    );
  }

  static List<String> _inferTodayHolidayNames(
    DateTime now,
    List<HolidayItem> holidays,
  ) {
    final todayIso = _toIsoDate(now);
    final names = <String>[];
    for (final holiday in holidays) {
      if (holiday.startDate.compareTo(todayIso) > 0) continue;
      if (holiday.endDate.compareTo(todayIso) < 0) continue;
      if (names.contains(holiday.label)) continue;
      names.add(holiday.label);
    }
    return names;
  }

  static String _toIsoDate(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }
}
