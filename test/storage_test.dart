import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:preconnect/tools/app_storage.dart';
import 'package:preconnect/tools/app_paths.dart';
import 'package:preconnect/api/custom_schedules.dart';
import 'package:preconnect/tools/snapshot_store.dart';
import 'package:preconnect/tools/image_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

class RejectingPreferences extends InMemorySharedPreferencesStore {
  RejectingPreferences() : super.empty();
  bool reject = false;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async =>
      reject ? false : super.setValue(valueType, key, value);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;
  final storage = AppStorage.instance;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('preconnect_storage_');
    SharedPreferences.setMockInitialValues({});
    await AppStorage.initialize(cacheDirectory: directory);
  });

  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test(
    'failed schedule and snapshot saves report persistence failure',
    () async {
      final backend = RejectingPreferences()..reject = true;
      SharedPreferencesStorePlatform.instance = backend;
      SharedPreferences.resetStatic();
      await AppStorage.initialize(cacheDirectory: directory);
      await expectLater(
        JsonSnapshotStore.write(key: 'test_snapshot', value: {'saved': false}),
        throwsStateError,
      );
      await expectLater(
        CustomSchedulesService().createItem(
          kind: 'event',
          title: 'Example Event',
          startTime: DateTime(2030),
        ),
        throwsStateError,
      );
    },
  );

  test(
    'large values survive reinitialization and small replacements',
    () async {
      final large = 'x' * (256 * 1024 + 1);
      await storage.setString('cache', large);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('cache'), '__fscache__:cache');
      await AppStorage.initialize(cacheDirectory: directory);
      expect(await storage.getString('cache'), large);
      await storage.setString('cache', 'small');
      await AppStorage.initialize(cacheDirectory: directory);
      expect(await storage.getString('cache'), 'small');
      expect(await File('${directory.path}/cache.json').exists(), isFalse);
    },
  );

  test('failed file writes preserve the last persisted value', () async {
    await storage.setString('cache', 'previous');
    await Directory('${directory.path}/cache.json').create();
    await expectLater(
      storage.setString('cache', 'x' * (256 * 1024 + 1)),
      throwsA(isA<FileSystemException>()),
    );
    expect(await storage.getString('cache'), 'previous');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('cache'), 'previous');
    await AppStorage.initialize(cacheDirectory: directory);
    expect(await storage.getString('cache'), 'previous');
  });


}
