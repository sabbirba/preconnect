import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:preconnect/api/planner_store.dart';
import 'package:preconnect/api/planner_state.dart';
import 'package:preconnect/tools/app_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;
  final store = PlannerStore.instance;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('preconnect_planner_');
    SharedPreferences.setMockInitialValues({});
    await AppStorage.initialize(cacheDirectory: directory);
  });

  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test('wishlist normalizes course codes and drops duplicates', () async {
    await store.saveWishlist(['cse 110', 'CSE110', 'mat110', '  ']);
    expect(await store.loadWishlist(), ['CSE110', 'MAT110']);
  });

  test('picks keep one section per course and skip bad rows', () async {
    await store.savePicks({'CSE110': 101, 'MAT110': 202});
    await AppStorage.instance.setStringList('planner_sections_v1', [
      ...(await AppStorage.instance.getStringList('planner_sections_v1'))!,
      'broken',
      'PHY111::abc',
    ]);
    expect(await store.loadPicks(), {'CSE110': 101, 'MAT110': 202});
  });

  test('planning before load keeps saved picks', () async {
    await store.saveWishlist(['CSE221']);
    await store.savePicks({'CSE221': 101});
    final controller = PlannerController(store: store);
    await controller.plan('ACT201', 202);
    expect(await store.loadPicks(), {'CSE221': 101, 'ACT201': 202});
    expect(await store.loadWishlist(), ['CSE221', 'ACT201']);
    controller.dispose();
  });
}
