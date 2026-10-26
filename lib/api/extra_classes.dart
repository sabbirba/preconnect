import 'dart:convert';

import 'package:preconnect/model/extra_class.dart';
import 'package:preconnect/tools/app_storage.dart';
import 'package:preconnect/tools/time_utils.dart';

class ExtraClassesStore {
  static const storageKey = 'extra_classes_v1';
  static Future<void> _pending = Future.value();

  Future<List<ExtraClass>> load() async {
    final raw = await AppStorage.instance.getString(storageKey);
    if (raw == null) return [];
    return (jsonDecode(raw) as List)
        .map(
          (item) => ExtraClass.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
  }

  Future<void> save(ExtraClass item) => _mutate((items) {
    if (item.section.semesterSessionId <= 0 ||
        item.section.sectionId <= 0 ||
        item.days.isEmpty ||
        item.selectedSection.sectionSchedule.classSchedules.isEmpty ||
        !item.days.every(
          (day) =>
              AppTime.weekdayFromName(day) != null &&
              item.section.sectionSchedule.classSchedules.any(
                (meeting) => meeting.day.toUpperCase() == day,
              ),
        )) {
      throw ArgumentError('Select at least one valid class day.');
    }
    return [...items.where((existing) => existing.key != item.key), item];
  });

  Future<void> remove(String key) =>
      _mutate((items) => items.where((item) => item.key != key).toList());

  Future<void> _mutate(List<ExtraClass> Function(List<ExtraClass>) update) {
    final result = _pending.then((_) async {
      final items = update(await load());
      await AppStorage.instance.setString(
        storageKey,
        jsonEncode(items.map((item) => item.toJson()).toList()),
      );
    });
    _pending = result.then<void>((_) {}, onError: (Object error) {});
    return result;
  }
}
