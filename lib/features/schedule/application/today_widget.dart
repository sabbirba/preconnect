import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:home_widget/home_widget.dart';
import 'package:preconnect/tools/platform_channels.dart';

class TodayItem {
  const TodayItem({
    required this.badge,
    required this.title,
    required this.subtitle,
    this.trailing = '',
    this.trailingSub = '',
    this.startMinutes = -1,
    this.endMinutes = -1,
  });

  factory TodayItem.fromJson(Map<String, dynamic> json) => TodayItem(
    badge: '${json['badge'] ?? ''}',
    title: '${json['title'] ?? ''}',
    subtitle: '${json['subtitle'] ?? ''}',
    trailing: '${json['trailing'] ?? ''}',
    trailingSub: '${json['trailingSub'] ?? ''}',
    startMinutes: (json['start'] as num?)?.toInt() ?? -1,
    endMinutes: (json['end'] as num?)?.toInt() ?? -1,
  );

  final String badge;
  final String title;
  final String subtitle;
  final String trailing;
  final String trailingSub;
  final int startMinutes;
  final int endMinutes;

  Map<String, dynamic> toJson() => {
    'badge': badge,
    'title': title,
    'subtitle': subtitle,
    'trailing': trailing,
    'trailingSub': trailingSub,
    'start': startMinutes,
    'end': endMinutes,
  };
}

class TodayWidgetData {
  const TodayWidgetData({
    required this.day,
    required this.title,
    required this.date,
    required this.items,
  });

  factory TodayWidgetData.fromJson(Map<String, dynamic> json) =>
      TodayWidgetData(
        day: (json['day'] as num?)?.toInt() ?? 0,
        title: '${json['title'] ?? ''}',
        date: '${json['date'] ?? ''}',
        items: [
          for (final item in json['items'] as List? ?? const [])
            if (item is Map) TodayItem.fromJson(item.cast<String, dynamic>()),
        ],
      );

  final int day;
  final String title;
  final String date;
  final List<TodayItem> items;

  Map<String, dynamic> toJson() => {
    'day': day,
    'title': title,
    'date': date,
    'items': [for (final item in items) item.toJson()],
  };
}

abstract final class TodayWidget {
  static const String _androidName = 'TodayWidgetProvider';
  static const String _iOSName = 'TodayWidget';
  static const String appGroupId =
      'group.com.sabbirba.preconnect.TodayWidgetExtension';
  static const MethodChannel _refreshChannel = MethodChannel(
    'preconnect/today_widget',
  );

  static bool get isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static Future<void> initialize() async {
    if (defaultTargetPlatform != TargetPlatform.iOS) return;
    try {
      await HomeWidget.setAppGroupId(appGroupId);
    } catch (_) {}
  }

  static const int dayCount = 7;
  static const String _daysKey = 'today_days';

  static int dayKey(DateTime date) =>
      date.year * 10000 + date.month * 100 + date.day;

  static Future<TodayWidgetData?> loadCurrent() async {
    if (!isSupported) return null;
    try {
      final raw = await HomeWidget.getWidgetData<String>(_daysKey);
      final days = [
        for (final day in jsonDecode(raw ?? '[]') as List)
          if (day is Map) TodayWidgetData.fromJson(day.cast<String, dynamic>()),
      ];
      final today = dayKey(DateTime.now());
      return days.where((day) => day.day == today).firstOrNull;
    } catch (_) {
      return null;
    }
  }

  static Future<void> sync(List<TodayWidgetData> days) async {
    if (!isSupported) return;
    try {
      await HomeWidget.saveWidgetData<String>(
        _daysKey,
        jsonEncode([for (final day in days) day.toJson()]),
      );
      await HomeWidget.updateWidget(
        androidName: _androidName,
        iOSName: _iOSName,
      );
    } catch (_) {}
  }

  static Future<void> finishBackgroundRefresh() async {
    try {
      await _refreshChannel.invokeMethod<void>('done');
    } catch (_) {}
  }

  static bool get _isAndroid =>
      isSupported && defaultTargetPlatform == TargetPlatform.android;

  static Future<bool> needsExactUpdates() async {
    if (!_isAndroid) return false;
    try {
      return await HomeWidget.canScheduleExactWidgetUpdates() == false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> allowExactUpdates() async {
    if (!_isAndroid) return;
    try {
      await const MethodChannel(
        PlatformChannels.backgroundPermission,
      ).invokeMethod<bool>('requestExactAlarms');
    } catch (_) {}
  }

  static Future<bool> isPinWidgetSupported() async {
    if (!_isAndroid) return false;
    try {
      final supported = await HomeWidget.isRequestPinWidgetSupported();
      return supported ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> requestPinWidget() async {
    if (!_isAndroid) return false;
    try {
      await HomeWidget.requestPinWidget(androidName: _androidName);
      return true;
    } catch (_) {
      return false;
    }
  }
}
