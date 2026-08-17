import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

class TodayItem {
  const TodayItem({
    required this.badge,
    required this.title,
    required this.subtitle,
    this.trailing = '',
    this.trailingSub = '',
  });

  final String badge;
  final String title;
  final String subtitle;
  final String trailing;
  final String trailingSub;
}

class TodayWidgetData {
  const TodayWidgetData({
    required this.title,
    required this.date,
    required this.items,
  });

  final String title;
  final String date;
  final List<TodayItem> items;
}

abstract final class TodayWidget {
  static const String _androidName = 'TodayWidgetProvider';
  static const String _iOSName = 'TodayWidget';
  static const String appGroupId =
      'group.com.sabbirba.preconnect.TodayWidgetExtension';

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

  static Future<TodayWidgetData?> loadCurrent() async {
    if (!isSupported) return null;
    try {
      final title = await HomeWidget.getWidgetData<String>('today_title') ?? '';
      final date = await HomeWidget.getWidgetData<String>('today_date') ?? '';
      final count =
          await HomeWidget.getWidgetData<int>('today_item_count') ?? 0;
      final items = <TodayItem>[];
      for (var i = 1; i <= count; i++) {
        final itemTitle =
            await HomeWidget.getWidgetData<String>('today_item${i}_title') ??
            '';
        if (itemTitle.isNotEmpty) {
          items.add(
            TodayItem(
              badge:
                  await HomeWidget.getWidgetData<String>(
                    'today_item${i}_badge',
                  ) ??
                  '',
              title: itemTitle,
              subtitle:
                  await HomeWidget.getWidgetData<String>(
                    'today_item${i}_subtitle',
                  ) ??
                  '',
              trailing:
                  await HomeWidget.getWidgetData<String>(
                    'today_item${i}_trailing',
                  ) ??
                  '',
              trailingSub:
                  await HomeWidget.getWidgetData<String>(
                    'today_item${i}_trailing_sub',
                  ) ??
                  '',
            ),
          );
        }
      }
      return TodayWidgetData(title: title, date: date, items: items);
    } catch (_) {
      return null;
    }
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
      final previousItemCount =
          await HomeWidget.getWidgetData<int>('today_item_count') ?? 0;
      final slotCount = previousItemCount > items.length
          ? previousItemCount
          : items.length;
      await HomeWidget.saveWidgetData<int>('today_item_count', items.length);
      for (var i = 0; i < slotCount; i++) {
        final item = i < items.length ? items[i] : null;
        final slot = i + 1;
        await HomeWidget.saveWidgetData<String>(
          'today_item${slot}_badge',
          item?.badge ?? '',
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
      await HomeWidget.updateWidget(
        androidName: _androidName,
        iOSName: _iOSName,
      );
    } catch (_) {}
  }

  static Future<bool> isPinWidgetSupported() async {
    if (!isSupported || defaultTargetPlatform != TargetPlatform.android) {
      return false;
    }
    try {
      final supported = await HomeWidget.isRequestPinWidgetSupported();
      return supported ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> requestPinWidget() async {
    if (!isSupported) return false;
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        await HomeWidget.requestPinWidget(androidName: _androidName);
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> clear() async {
    if (!isSupported) return;
    try {
      await HomeWidget.saveWidgetData<String>('today_title', '');
      await HomeWidget.saveWidgetData<String>('today_date', '');
      await HomeWidget.saveWidgetData<int>('today_item_count', 0);
      await HomeWidget.updateWidget(
        androidName: _androidName,
        iOSName: _iOSName,
      );
    } catch (_) {}
  }
}
