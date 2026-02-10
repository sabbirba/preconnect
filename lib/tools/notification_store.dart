import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:preconnect/model/notification_item.dart';

class NotificationStore {
  static const String _key = 'notifications_log';

  static Future<List<NotificationItem>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? const [];
    final items = <NotificationItem>[];
    for (final entry in raw) {
      try {
        final decoded = jsonDecode(entry);
        if (decoded is Map) {
          items.add(
            NotificationItem.fromJson(Map<String, dynamic>.from(decoded)),
          );
        }
      } catch (_) {}
    }
    items.sort((a, b) => b.timeIso.compareTo(a.timeIso));
    return items;
  }

  static Future<void> save(List<NotificationItem> items) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = items.map((e) => jsonEncode(e.toJson())).toList();
    await prefs.setStringList(_key, raw);
  }

  static Future<void> add(NotificationItem item) async {
    final items = await load();
    items.insert(0, item);
    await save(items);
  }

  static Future<void> delete(int id) async {
    final items = await load();
    items.removeWhere((e) => e.id == id);
    await save(items);
  }
}
