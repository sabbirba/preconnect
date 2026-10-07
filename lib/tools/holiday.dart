import 'dart:async';
import 'dart:convert';

import 'package:preconnect/api/api_client.dart';
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/api/notification.dart';
import 'package:preconnect/tools/app_storage.dart';

typedef HolidayItem = ({String startDate, String endDate, String label});

class HolidayStatus {
  const HolidayStatus({
    required this.isTodayHoliday,
    required this.todayHolidayNames,
    required this.nextHolidaysThisYear,
    this.allHolidays = const <HolidayItem>[],
  });

  static const HolidayStatus empty = HolidayStatus(
    isTodayHoliday: false,
    todayHolidayNames: <String>[],
    nextHolidaysThisYear: <HolidayItem>[],
    allHolidays: <HolidayItem>[],
  );

  final bool isTodayHoliday;
  final List<String> todayHolidayNames;
  final List<HolidayItem> nextHolidaysThisYear;
  final List<HolidayItem> allHolidays;

  String get displayNames => todayHolidayNames.join(' • ');

  bool isHolidayOn(DateTime date) => holidayNameOn(date) != null;

  String? holidayNameOn(DateTime date) {
    final iso = HolidayTiming.toIsoDate(date);
    final names = <String>[];
    final items = allHolidays.isNotEmpty ? allHolidays : nextHolidaysThisYear;
    for (final h in items) {
      if (h.startDate.compareTo(iso) <= 0 && h.endDate.compareTo(iso) >= 0) {
        final label = h.label;
        if (names.any(
          (n) =>
              n.toLowerCase() == label.toLowerCase() ||
              n.toLowerCase().contains(label.toLowerCase()) ||
              label.toLowerCase().contains(n.toLowerCase()),
        )) {
          continue;
        }
        names.add(label);
      }
    }
    if (names.isNotEmpty) {
      return names.join(' • ');
    }
    final todayIso = HolidayTiming.toIsoDate(DateTime.now());
    if (iso == todayIso && isTodayHoliday && todayHolidayNames.isNotEmpty) {
      return displayNames;
    }
    return null;
  }

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
      'allHolidays': allHolidays
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
    final nextHolidays = _itemsFromAny(json['nextHolidaysThisYear']);
    final allHolidays = _itemsFromAny(json['allHolidays']);
    return HolidayStatus(
      isTodayHoliday: json['isTodayHoliday'] == true,
      todayHolidayNames: _namesFromAny(json['todayHolidays']),
      nextHolidaysThisYear: nextHolidays,
      allHolidays: allHolidays.isNotEmpty ? allHolidays : nextHolidays,
    );
  }

  static HolidayStatus fromCache(dynamic json) {
    if (json is! Map) return HolidayStatus.empty;
    final map = Map<String, dynamic>.from(json);
    final nextHolidays = _itemsFromAny(map['nextHolidaysThisYear']);
    final allHolidays = _itemsFromAny(map['allHolidays']);
    return HolidayStatus(
      isTodayHoliday: map['isTodayHoliday'] == true,
      todayHolidayNames: _namesFromAny(map['todayHolidayNames']),
      nextHolidaysThisYear: nextHolidays,
      allHolidays: allHolidays.isNotEmpty ? allHolidays : nextHolidays,
    );
  }

  static bool isAcademicOffDay(String eventName) {
    final lower = eventName.toLowerCase();
    return lower.contains('closed') ||
        lower.contains('holiday') ||
        lower.contains('vacation') ||
        lower.contains('recess') ||
        lower.contains('eid') ||
        lower.contains('puja');
  }

  static String cleanOffDayLabel(String raw) {
    var label = raw
        .replaceAll(
          RegExp(r'\s*\(University Closed\)', caseSensitive: false),
          '',
        )
        .replaceAll(
          RegExp(r'\s*-\s*University [Cc]losed', caseSensitive: false),
          '',
        )
        .replaceAll(
          RegExp(r'^\s*University [Cc]losed\s*-\s*', caseSensitive: false),
          '',
        )
        .replaceAll('*', '')
        .trim();
    while (label.endsWith('-') || label.endsWith('–')) {
      label = label.substring(0, label.length - 1).trim();
    }
    while (label.startsWith('-') || label.startsWith('–')) {
      label = label.substring(1).trim();
    }
    if (label.isEmpty || label.toLowerCase() == 'university closed') {
      return 'University Holiday';
    }
    return label;
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
      final cleaned = _clean(raw);
      if (cleaned == null) continue;
      final name = cleanOffDayLabel(cleaned);
      if (!seen.add(name)) continue;
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
      final raw = _clean(map['label']) ?? _clean(map['name']);
      if (startDate == null || endDate == null || raw == null) continue;
      final label = cleanOffDayLabel(raw);
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
    final todayIso = HolidayTiming.toIsoDate(DateTime.now());
    final nextHolidays = <HolidayItem>[];
    final allHolidays = <HolidayItem>[];
    final todayHolidayNames = <String>[];
    final nextSeen = <String>{};
    final todaySeen = <String>{};
    final allSeen = <String>{};

    for (final item in source) {
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);
      final startDate = _clean(map['startDate']);
      final endDate = _clean(map['endDate']) ?? startDate;
      final rawLabel = _clean(map['label']) ?? _clean(map['name']);
      if (startDate == null || endDate == null || rawLabel == null) continue;
      final label = cleanOffDayLabel(rawLabel);

      final key = '$startDate|$endDate|$label';
      if (allSeen.add(key)) {
        allHolidays.add((startDate: startDate, endDate: endDate, label: label));
      }

      final isCurrentOrUpcoming = endDate.compareTo(todayIso) >= 0;
      if (isCurrentOrUpcoming && nextSeen.add(key)) {
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
    allHolidays.sort((a, b) => a.startDate.compareTo(b.startDate));
    return HolidayStatus(
      isTodayHoliday: todayHolidayNames.isNotEmpty,
      todayHolidayNames: todayHolidayNames,
      nextHolidaysThisYear: nextHolidays,
      allHolidays: allHolidays,
    );
  }
}

class HolidayTiming {
  HolidayTiming._();

  static const String _storageKey = 'holiday_status_v1';
  static const List<String> _statusUrls = <String>[ApiConfig.holidayStatusUrl];

  static HolidayStatus? _cachedStatus;
  static Future<HolidayStatus>? _inflight;

  static HolidayStatus get cachedStatus {
    if (_cachedStatus != null) return _cachedStatus!;
    final raw = AppStorage.instance.getStringSync(_storageKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        _cachedStatus = HolidayStatus.fromCache(decoded);
        return _cachedStatus!;
      } catch (_) {}
    }
    return HolidayStatus.empty;
  }

  static Future<HolidayStatus> getTodayStatus({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _cachedStatus != null) {
      return _cachedStatus!;
    }
    if (_inflight != null) return _inflight!;

    _inflight = _refreshStatus(forceRefresh: forceRefresh);
    return _inflight!;
  }

  static Future<HolidayStatus> _refreshStatus({
    required bool forceRefresh,
  }) async {
    try {
      final holidayResult = await _fetchTodayStatus(forceRefresh: forceRefresh);
      final academicItems = await _fetchAcademicOffDays(
        forceRefresh: forceRefresh,
      );
      final baseStatus = holidayResult.fromNetwork
          ? holidayResult.value
          : _fallbackOfflineStatus(DateTime.now());
      final combined = _combineHolidays(baseStatus, academicItems);
      _cachedStatus = combined;
      unawaited(
        AppStorage.instance.setString(
          _storageKey,
          jsonEncode(combined.toCacheJson()),
        ),
      );
      return combined;
    } finally {
      _inflight = null;
    }
  }

  static Future<List<HolidayItem>> _fetchAcademicOffDays({
    required bool forceRefresh,
  }) async {
    try {
      final rows = await FeedService().fetchList(
        path: ApiConfig.academicDatesUrl,
        cacheKey: 'academic_dates_v1',
        ttl: const Duration(days: 30),
        forceRefresh: forceRefresh,
      );
      final items = <HolidayItem>[];
      for (final row in rows) {
        final rawName = HolidayStatus._clean(row['event_name']);
        final startDate = HolidayStatus._clean(row['start_date']);
        final endDate = HolidayStatus._clean(row['end_date']) ?? startDate;
        if (rawName == null || startDate == null || endDate == null) continue;
        if (!HolidayStatus.isAcademicOffDay(rawName)) continue;
        final label = HolidayStatus.cleanOffDayLabel(rawName);
        items.add((startDate: startDate, endDate: endDate, label: label));
      }
      return items;
    } catch (_) {
      return const <HolidayItem>[];
    }
  }

  static HolidayStatus _combineHolidays(
    HolidayStatus base,
    List<HolidayItem> extra,
  ) {
    if (extra.isEmpty && base.allHolidays.isNotEmpty) {
      return base;
    }
    final todayIso = toIsoDate(DateTime.now());
    final allList = <HolidayItem>[
      ...base.allHolidays,
      ...base.nextHolidaysThisYear,
      ...extra,
    ];
    final nextHolidays = <HolidayItem>[];
    final todayNames = <String>[...base.todayHolidayNames];
    final allCombined = <HolidayItem>[];
    final seen = <String>{};

    for (final item in allList) {
      final duplicate = allCombined.indexWhere(
        (existing) =>
            existing.startDate == item.startDate &&
            existing.endDate == item.endDate &&
            (existing.label.toLowerCase() == item.label.toLowerCase() ||
                existing.label.toLowerCase().contains(
                  item.label.toLowerCase(),
                ) ||
                item.label.toLowerCase().contains(
                  existing.label.toLowerCase(),
                )),
      );
      if (duplicate != -1) continue;
      final key = '${item.startDate}|${item.endDate}|${item.label}';
      if (!seen.add(key)) continue;
      allCombined.add(item);

      final isCurrentOrUpcoming = item.endDate.compareTo(todayIso) >= 0;
      if (isCurrentOrUpcoming) {
        nextHolidays.add(item);
      }

      if (item.startDate.compareTo(todayIso) <= 0 &&
          item.endDate.compareTo(todayIso) >= 0) {
        final label = item.label;
        if (!todayNames.any(
          (n) =>
              n.toLowerCase() == label.toLowerCase() ||
              n.toLowerCase().contains(label.toLowerCase()) ||
              label.toLowerCase().contains(n.toLowerCase()),
        )) {
          todayNames.add(label);
        }
      }
    }

    nextHolidays.sort((a, b) => a.startDate.compareTo(b.startDate));
    allCombined.sort((a, b) => a.startDate.compareTo(b.startDate));

    return HolidayStatus(
      isTodayHoliday: todayNames.isNotEmpty,
      todayHolidayNames: todayNames,
      nextHolidaysThisYear: nextHolidays,
      allHolidays: allCombined,
    );
  }

  static Future<({HolidayStatus value, bool fromNetwork})> _fetchTodayStatus({
    required bool forceRefresh,
  }) async {
    for (final url in _statusUrls) {
      try {
        final response = await ApiClient().publicGet(
          url,
          acceptedStatusCodes: const <int>{200},
          cacheDuration: forceRefresh
              ? Duration.zero
              : const Duration(minutes: 5),
        );

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
    final cached = cachedStatus;
    if (cached.allHolidays.isNotEmpty ||
        cached.nextHolidaysThisYear.isNotEmpty) {
      return cached;
    }
    final inferredToday = _inferTodayHolidayNames(now, const <HolidayItem>[]);
    return HolidayStatus(
      isTodayHoliday: inferredToday.isNotEmpty,
      todayHolidayNames: inferredToday,
      nextHolidaysThisYear: const <HolidayItem>[],
      allHolidays: const <HolidayItem>[],
    );
  }

  static List<String> _inferTodayHolidayNames(
    DateTime now,
    List<HolidayItem> holidays,
  ) {
    final todayIso = toIsoDate(now);
    return holidays
        .where(
          (h) =>
              h.startDate.compareTo(todayIso) <= 0 &&
              h.endDate.compareTo(todayIso) >= 0,
        )
        .map((h) => h.label)
        .toSet()
        .toList();
  }

  static String toIsoDate(DateTime date) =>
      date.toIso8601String().substring(0, 10);
}
