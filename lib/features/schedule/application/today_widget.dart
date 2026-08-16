import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

class TodayItem {
  const TodayItem({
    required this.badge,
    required this.badgeColor,
    required this.title,
    required this.subtitle,
    this.trailing = '',
    this.trailingSub = '',
  });

  final String badge;
  final String badgeColor;
  final String title;
  final String subtitle;
  final String trailing;
  final String trailingSub;
}

abstract final class TodayWidget {
  static const String _androidName = 'TodayWidgetProvider';
  static const String _iOSName = 'TodayWidget';
  static const String appGroupId = 'group.com.sabbirba.preconnect.widget';
  static const int _maxItems = 3;
  static const String primaryColor = '#FF1E6BE3';
  static const String accentColor = '#FF22B573';

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

  static Future<void> sync({
    required String title,
    required String date,
    required List<TodayItem> items,
  }) async {
    if (!isSupported) return;

    try {
      await HomeWidget.saveWidgetData<String>('today_title', title);
      await HomeWidget.saveWidgetData<String>('today_date', date);
      await HomeWidget.saveWidgetData<String>(
        'today_date_key',
        DateTime.now().toIso8601String().substring(0, 10),
      );
      for (var i = 0; i < _maxItems; i++) {
        final item = i < items.length ? items[i] : null;
        final slot = i + 1;
        await HomeWidget.saveWidgetData<String>(
          'today_item${slot}_badge',
          item?.badge ?? '',
        );
        await HomeWidget.saveWidgetData<String>(
          'today_item${slot}_badge_color',
          item?.badgeColor ?? primaryColor,
        );
        await HomeWidget.saveWidgetData<String>(
          'today_item${slot}_title',
          item?.title ?? '',
        );
        await HomeWidget.saveWidgetData<String>(
          'today_item${slot}_subtitle',
          item?.subtitle ?? '',
        );
        await HomeWidget.saveWidgetData<String>(
          'today_item${slot}_trailing',
          item?.trailing ?? '',
        );
        await HomeWidget.saveWidgetData<String>(
          'today_item${slot}_trailing_sub',
          item?.trailingSub ?? '',
        );
      }
      await HomeWidget.saveWidgetData<String>('today_syncing', '0');
      await HomeWidget.updateWidget(
        androidName: _androidName,
        iOSName: _iOSName,
      );
    } catch (_) {}
  }

  static Future<void> setSyncing(bool syncing) async {
    if (!isSupported) return;
    try {
      await HomeWidget.saveWidgetData<String>(
        'today_syncing',
        syncing ? '1' : '0',
      );
      await HomeWidget.updateWidget(
        androidName: _androidName,
        iOSName: _iOSName,
      );
    } catch (_) {}
  }
}
