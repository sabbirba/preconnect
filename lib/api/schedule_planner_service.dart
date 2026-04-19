import 'package:preconnect/api/app_preferences_store.dart';
import 'package:preconnect/model/schedule_planner_item.dart';

class SchedulePlannerService {
  SchedulePlannerService._internal();

  static final SchedulePlannerService _instance =
      SchedulePlannerService._internal();
  factory SchedulePlannerService() => _instance;

  final AppPreferencesStore _store = AppPreferencesStore();

  static const String cacheKey = 'schedule_planner_items_v1';

  Future<List<SchedulePlannerItem>> getItems({
    bool forceRefresh = false,
  }) async {
    final cached = await _readCachedItems();
    return cached ?? const <SchedulePlannerItem>[];
  }

  Future<List<SchedulePlannerItem>?> getCachedItems() async {
    return _readCachedItems();
  }

  Future<List<SchedulePlannerItem>> autoCompleteOverdueItems(
    List<SchedulePlannerItem> items,
  ) async {
    final overdueItems = items.where((item) => item.isOverdue).toList();
    if (overdueItems.isEmpty) return items;

    final updatedItems = List<SchedulePlannerItem>.from(items);
    for (final overdue in overdueItems) {
      final updated = await _markItemDone(overdue);
      for (var i = 0; i < updatedItems.length; i++) {
        if (updatedItems[i].itemId == updated.itemId) {
          updatedItems[i] = updated;
          break;
        }
      }
    }

    updatedItems.sort(_compareItems);
    await _writeCache(updatedItems);
    return updatedItems;
  }

  Future<SchedulePlannerItem> createItem({
    required String kind,
    required String title,
    required DateTime startTime,
    DateTime? endTime,
    DateTime? reminderAt,
    String courseCode = '',
    String sectionName = '',
    String notes = '',
    bool isDone = false,
  }) async {
    final now = DateTime.now().toUtc();
    final item = SchedulePlannerItem(
      itemId: await _nextItemId(),
      kind: kind,
      title: title,
      courseCode: courseCode,
      sectionName: sectionName,
      startTime: startTime,
      endTime: endTime,
      reminderAt: reminderAt,
      notes: notes,
      isDone: isDone,
      createdAt: now,
      updatedAt: now,
    );
    await _upsertCacheItem(item);
    return item;
  }

  Future<SchedulePlannerItem> updateItem({
    required int itemId,
    String? kind,
    String? title,
    DateTime? startTime,
    DateTime? endTime,
    bool clearEndTime = false,
    DateTime? reminderAt,
    bool clearReminderAt = false,
    String? courseCode,
    String? sectionName,
    String? notes,
    bool? isDone,
  }) async {
    final current = await _readCachedItems() ?? const <SchedulePlannerItem>[];
    final index = current.indexWhere((item) => item.itemId == itemId);
    if (index < 0) {
      throw StateError('Schedule planner item not found: $itemId');
    }

    final existing = current[index];
    final updated = existing.copyWith(
      kind: kind,
      title: title,
      startTime: startTime,
      endTime: endTime,
      clearEndTime: clearEndTime,
      reminderAt: reminderAt,
      clearReminderAt: clearReminderAt,
      courseCode: courseCode,
      sectionName: sectionName,
      notes: notes,
      isDone: isDone,
    );

    await _upsertCacheItem(updated);
    return updated;
  }

  Future<SchedulePlannerItem> _markItemDone(SchedulePlannerItem item) async {
    try {
      return await updateItem(itemId: item.itemId, isDone: true);
    } catch (_) {
      final updated = item.copyWith(isDone: true);
      await _upsertCacheItem(updated);
      return updated;
    }
  }

  Future<void> deleteItem(int itemId) async {
    final cached = await _readCachedItems();
    if (cached == null) return;
    final updated = cached.where((item) => item.itemId != itemId).toList();
    await _writeCache(updated);
  }

  Future<int> _nextItemId() async {
    final current = await _readCachedItems();
    if (current == null || current.isEmpty) return 1;
    final maxId = current.fold<int>(0, (prev, item) {
      return item.itemId > prev ? item.itemId : prev;
    });
    return maxId + 1;
  }

  Future<List<SchedulePlannerItem>?> _readCachedItems() async {
    try {
      final raw = await _store.getJsonMap(cacheKey);
      final items = raw?['items'];
      if (items is! List) return null;
      return items
          .whereType<Map>()
          .map(
            (item) =>
                SchedulePlannerItem.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList(growable: false);
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeCache(List<SchedulePlannerItem> items) async {
    try {
      await _store.setJson(cacheKey, <String, dynamic>{
        'ts': DateTime.now().millisecondsSinceEpoch,
        'items': items.map((item) => item.toJson()).toList(growable: false),
      });
    } catch (_) {}
  }

  Future<void> _upsertCacheItem(SchedulePlannerItem item) async {
    final current = await _readCachedItems();
    if (current == null) {
      await _writeCache(<SchedulePlannerItem>[item]);
      return;
    }
    final next = <SchedulePlannerItem>[
      for (final existing in current)
        if (existing.itemId != item.itemId) existing,
      item,
    ];
    next.sort((a, b) {
      final doneCompare = a.isDone == b.isDone
          ? 0
          : a.isDone
              ? 1
              : -1;
      if (doneCompare != 0) return doneCompare;
      final dueCompare = a.startTime.compareTo(b.startTime);
      if (dueCompare != 0) return dueCompare;
      return b.createdAt.compareTo(a.createdAt);
    });
    await _writeCache(next);
  }

  int _compareItems(SchedulePlannerItem a, SchedulePlannerItem b) {
    final doneCompare = a.isDone == b.isDone
        ? 0
        : a.isDone
            ? 1
            : -1;
    if (doneCompare != 0) return doneCompare;
    final dueCompare = a.startTime.compareTo(b.startTime);
    if (dueCompare != 0) return dueCompare;
    return b.createdAt.compareTo(a.createdAt);
  }
}
