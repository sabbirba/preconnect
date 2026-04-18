import 'dart:convert';

import 'package:preconnect/api/api_client.dart';
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/api/app_preferences_store.dart';
import 'package:preconnect/model/schedule_planner_item.dart';

class SchedulePlannerService {
  SchedulePlannerService._internal();

  static final SchedulePlannerService _instance =
      SchedulePlannerService._internal();
  factory SchedulePlannerService() => _instance;

  final ApiClient _client = ApiClient();
  final AppPreferencesStore _store = AppPreferencesStore();

  static const String _cacheKey = 'schedule_planner_items_v1';

  Future<List<SchedulePlannerItem>> getItems({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh) {
      final cached = await _readCachedItems();
      if (cached != null) return cached;
    }

    try {
      final response = await _client.authenticatedGet(
        '${ApiConfig.seatStatusProxyBase}/v1/schedule-planner',
      );
      if (response.statusCode != 200) {
        final cached = await _readCachedItems();
        if (cached != null) {
          return cached;
        }
        throw ApiException(response.statusCode, response.body);
      }
      try {
        final decoded = jsonDecode(response.body);
        final items = _decodeItems(decoded);
        await _writeCache(items);
        return items;
      } catch (e) {
        final cached = await _readCachedItems();
        if (cached != null) {
          return cached;
        }
        rethrow;
      }
    } catch (e) {
      final cached = await _readCachedItems();
      if (cached != null) {
        return cached;
      }
      rethrow;
    }
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
    final response = await _client.authenticatedRequest(
      'POST',
      '${ApiConfig.seatStatusProxyBase}/v1/schedule-planner',
      body: jsonEncode(<String, dynamic>{
        'kind': kind,
        'title': title,
        'courseCode': courseCode,
        'sectionName': sectionName,
        'startTime': startTime.toUtc().toIso8601String(),
        'endTime': endTime?.toUtc().toIso8601String(),
        'reminderAt': reminderAt?.toUtc().toIso8601String(),
        'notes': notes,
        'isDone': isDone,
      }),
      additionalHeaders: const {'Content-Type': 'application/json'},
      acceptedStatusCodes: const {200, 201},
    );
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    var item = SchedulePlannerItem.fromJson(
      Map<String, dynamic>.from(decoded['item'] as Map),
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
    final payload = <String, dynamic>{};
    if (kind != null) payload['kind'] = kind;
    if (title != null) payload['title'] = title;
    if (startTime != null) {
      payload['startTime'] = startTime.toUtc().toIso8601String();
    }
    if (clearEndTime) {
      payload['endTime'] = null;
    } else if (endTime != null) {
      payload['endTime'] = endTime.toUtc().toIso8601String();
    }
    if (clearReminderAt) {
      payload['reminderAt'] = null;
    } else if (reminderAt != null) {
      payload['reminderAt'] = reminderAt.toUtc().toIso8601String();
    }
    if (courseCode != null) payload['courseCode'] = courseCode;
    if (sectionName != null) payload['sectionName'] = sectionName;
    if (notes != null) payload['notes'] = notes;
    if (isDone != null) payload['isDone'] = isDone;

    final response = await _client.authenticatedRequest(
      'PATCH',
      '${ApiConfig.seatStatusProxyBase}/v1/schedule-planner/$itemId',
      body: jsonEncode(payload),
      additionalHeaders: const {'Content-Type': 'application/json'},
      acceptedStatusCodes: const {200},
    );
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw FormatException('Expected Map from API response');
      }
      final itemData = decoded['item'];
      if (itemData is! Map) {
        throw FormatException('Expected item Map in API response');
      }
      var item = SchedulePlannerItem.fromJson(
        Map<String, dynamic>.from(itemData),
      );
      if (isDone != null && item.isDone != isDone) {
        item = item.copyWith(isDone: isDone);
      }
      await _upsertCacheItem(item);
      return item;
    } catch (e) {
      rethrow;
    }
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
    await _client.authenticatedRequest(
      'DELETE',
      '${ApiConfig.seatStatusProxyBase}/v1/schedule-planner/$itemId',
      acceptedStatusCodes: const {200},
    );
    final cached = await _readCachedItems();
    if (cached == null) return;
    final updated = cached.where((item) => item.itemId != itemId).toList();
    await _writeCache(updated);
  }

  Future<List<SchedulePlannerItem>?> _readCachedItems() async {
    try {
      final raw = await _store.getJsonMap(_cacheKey);
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
      await _store.setJson(_cacheKey, <String, dynamic>{
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

  List<SchedulePlannerItem> _decodeItems(dynamic decoded) {
    final rawItems = decoded is Map ? decoded['items'] : null;
    if (rawItems is! List) return const <SchedulePlannerItem>[];
    final items = rawItems
        .whereType<Map>()
        .map(
          (item) =>
              SchedulePlannerItem.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList(growable: false);
    items.sort(_compareItems);
    return items;
  }
}
