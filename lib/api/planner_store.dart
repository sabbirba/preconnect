import 'package:preconnect/tools/app_storage.dart';
import 'package:preconnect/tools/routine_clash.dart';
import 'package:preconnect/tools/storage_keys.dart';

class PlannerStore {
  PlannerStore._();

  static final PlannerStore instance = PlannerStore._();

  Future<List<String>> loadWishlist() async {
    final values =
        await AppStorage.instance.getStringList(StorageKeys.plannerWishlist) ??
        const <String>[];
    final seen = <String>{};
    return <String>[
      for (final value in values)
        if (planCourseKey(value) case final code
            when code.isNotEmpty && seen.add(code))
          code,
    ];
  }

  Future<void> saveWishlist(List<String> courses) {
    return AppStorage.instance.setStringList(
      StorageKeys.plannerWishlist,
      courses,
    );
  }

  Future<Map<String, int>> loadPicks() async {
    final values =
        await AppStorage.instance.getStringList(StorageKeys.plannerSections) ??
        const <String>[];
    final picks = <String, int>{};
    for (final value in values) {
      final parts = value.split('::');
      if (parts.length != 2) continue;
      final code = planCourseKey(parts.first);
      final sectionId = int.tryParse(parts.last);
      if (code.isEmpty || sectionId == null) continue;
      picks[code] = sectionId;
    }
    return picks;
  }

  Future<void> savePicks(Map<String, int> picks) {
    return AppStorage.instance.setStringList(StorageKeys.plannerSections, [
      for (final entry in picks.entries) '${entry.key}::${entry.value}',
    ]);
  }
}
