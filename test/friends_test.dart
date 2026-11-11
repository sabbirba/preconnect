import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:preconnect/api/friend_store.dart';
import 'package:preconnect/model/friend_schedule.dart';
import 'package:preconnect/pages/scan_schedule.dart';
import 'package:preconnect/tools/app_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _pack(Object value) =>
    base64.encode(GZipEncoder().encode(utf8.encode(jsonEncode(value))));

String _friendCode(String id, String name) => _pack({
  'name': name,
  'id': id,
  'photoFilePath': null,
  'courses': const <Object>[],
  'semester': 'Test 2030',
});

String _exportCode(List<String> codes) => _pack({
  'type': 'friend_schedules_export',
  'version': 1,
  'schedules': codes,
});

FriendSchedule _friend(String id, String name) => FriendSchedule(
  name: name,
  id: id,
  photoFilePath: null,
  photoUrl: null,
  courses: const [],
);

Future<void> _pump(
  WidgetTester tester,
  Map<String, FriendSchedule> added, {
  VoidCallback? onDone,
  VoidCallback? onScanAnother,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: FriendsAddedView(
            added: added,
            onDone: onDone ?? () {},
            onScanAnother: onScanAnother,
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('shows the card of the friend that was just added', (
    tester,
  ) async {
    var done = false;
    await _pump(tester, {
      'code-a': _friend('test-a', 'Test Student A'),
    }, onDone: () => done = true);

    expect(find.text('Schedule Added'), findsOneWidget);
    expect(find.text('Test Student A'), findsOneWidget);
    expect(find.text('No schedule shared'), findsOneWidget);
    expect(find.text('T'), findsOneWidget);
    expect(find.text('Scan Another'), findsNothing);

    await tester.tap(find.text('Done'));
    expect(done, isTrue);
  });

  testWidgets('lists every friend from a multi-friend code', (tester) async {
    var scanAgain = false;
    await _pump(tester, {
      'code-a': _friend('test-a', 'Test Student A'),
      'code-b': _friend('test-b', 'Mock Student B'),
    }, onScanAnother: () => scanAgain = true);

    expect(find.text('Schedules Added'), findsOneWidget);
    expect(find.text('Test Student A'), findsOneWidget);
    expect(find.text('Mock Student B'), findsOneWidget);

    await tester.tap(find.text('Scan Another'));
    expect(scanAgain, isTrue);
  });

  group('friends export and import', () {
    late Directory directory;
    final store = FriendScheduleStore();

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('preconnect_friends_');
      SharedPreferences.setMockInitialValues({});
      await AppStorage.initialize(cacheDirectory: directory);
    });

    tearDown(() => directory.delete(recursive: true));

    test('an export of several friends imports every one of them', () async {
      final codes = [
        _friendCode('test-a', 'Test Student A'),
        _friendCode('test-b', 'Mock Student B'),
        _friendCode('test-c', 'Sample Student C'),
      ];
      final added = await store.importPayload(_exportCode(codes));
      expect(added.values.map((friend) => friend.name), [
        'Test Student A',
        'Mock Student B',
        'Sample Student C',
      ]);
      final saved = await store.loadSnapshot();
      expect(saved.encodedSchedules, codes);
    });

    test(
      'importing the same export again does not duplicate friends',
      () async {
        final export = _exportCode([
          _friendCode('test-a', 'Test Student A'),
          _friendCode('test-b', 'Mock Student B'),
        ]);
        await store.importPayload(export);
        await store.importPayload(export);
        expect((await store.loadSnapshot()).encodedSchedules, hasLength(2));
      },
    );

    test(
      'an export keeps friends already saved and updates changed ones',
      () async {
        await store.importPayload(_friendCode('test-a', 'Old Name A'));
        await store.importPayload(_friendCode('test-z', 'Test Student Z'));
        await store.importPayload(
          _exportCode([
            _friendCode('test-a', 'Test Student A'),
            _friendCode('test-b', 'Mock Student B'),
          ]),
        );
        final names = (await store.loadSnapshot()).encodedSchedules
            .map((code) => FriendScheduleStore.parseSchedulePayload(code)!.name)
            .toSet();
        expect(names, {'Test Student Z', 'Test Student A', 'Mock Student B'});
      },
    );

    test('a broken export is rejected without saving anything', () async {
      await expectLater(
        store.importPayload(_exportCode(['not-a-friend-code'])),
        throwsFormatException,
      );
      expect((await store.loadSnapshot()).encodedSchedules, isEmpty);
    });
  });
}
