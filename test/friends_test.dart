import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:preconnect/api/friend_store.dart';
import 'package:preconnect/model/friend_schedule.dart';
import 'package:preconnect/tools/app_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _encodeSchedule({required String id, required String name}) {
  final json = jsonEncode({
    'name': name,
    'id': id,
    'photoFilePath': '',
    'courses': <Map<String, dynamic>>[],
    'semester': 'Summer 2026',
  });
  return base64.encode(GZipEncoder().encode(utf8.encode(json)));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FriendScheduleStore', () {
    test(
      'loads modern friend_schedules_encoded_v1 and metadata_v1 keys',
      () async {
        final base64Encoded = _encodeSchedule(
          id: '20101234',
          name: 'Test Student',
        );

        SharedPreferences.setMockInitialValues(<String, Object>{
          'friend_schedules_encoded_v1': jsonEncode(<String>[base64Encoded]),
          'friend_schedules_metadata_v1': jsonEncode(<String, dynamic>{
            '20101234': <String, dynamic>{
              'friendId': '20101234',
              'nickname': 'Bestie',
              'isFavorite': true,
            },
          }),
        });

        final store = FriendScheduleStore();
        final snapshot = await store.loadSnapshot();

        expect(snapshot.encodedSchedules, hasLength(1));
        expect(snapshot.encodedSchedules.first, equals(base64Encoded));
        expect(snapshot.metadata, contains('20101234'));
        expect(snapshot.metadata['20101234']?.nickname, equals('Bestie'));
        expect(snapshot.metadata['20101234']?.isFavorite, isTrue);

        await AppStorage.instance.clear();
      },
    );

    test('accepts only the exact compressed schedule payload', () {
      final jsonPayload = jsonEncode({
        'name': 'Exact Friend',
        'id': '20261111',
        'photoFilePath': '',
        'courses': <Map<String, dynamic>>[],
        'semester': 'Summer 2026',
      });
      final encoded = base64.encode(
        GZipEncoder().encode(utf8.encode(jsonPayload)),
      );

      final friend = FriendScheduleStore.parseSchedulePayload(encoded);
      expect(friend?.id, '20261111');
      expect(friend?.name, 'Exact Friend');
      expect(
        FriendScheduleStore.parseSchedulePayload(
          base64.encode(utf8.encode(jsonPayload)),
        ),
        isNull,
      );
      expect(FriendScheduleStore.parseSchedulePayload(jsonPayload), isNull);
    });

    test('accepts only the exact compressed export payload', () {
      final exportPackage = jsonEncode({
        'type': 'friend_schedules_export',
        'version': 1,
        'schedules': ['item1', 'item2'],
      });
      final gzipped = GZipEncoder().encode(utf8.encode(exportPackage));
      final encoded = base64.encode(gzipped);
      expect(
        FriendScheduleStore.extractExportSchedules(encoded),
        equals(['item1', 'item2']),
      );
      expect(
        FriendScheduleStore.extractExportSchedules(
          base64.encode(utf8.encode(exportPackage)),
        ),
        isNull,
      );
      expect(FriendScheduleStore.extractExportSchedules(exportPackage), isNull);

      final malformed = jsonEncode({
        'type': 'friend_schedules_export',
        'version': 1,
        'schedules': ['item1', 2],
      });
      final malformedEncoded = base64.encode(
        GZipEncoder().encode(utf8.encode(malformed)),
      );
      expect(
        FriendScheduleStore.extractExportSchedules(malformedEncoded),
        isNull,
      );
    });

    test('upserts and removes schedules by id', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});

      final store = FriendScheduleStore();
      final b64 = _encodeSchedule(id: '99999', name: 'Unique');

      await store.importPayload(b64);
      var snapshot = await store.loadSnapshot();
      expect(snapshot.encodedSchedules, contains(b64));

      final updated = _encodeSchedule(id: '99999', name: 'Updated');
      await store.importPayload(updated);
      snapshot = await store.loadSnapshot();
      expect(snapshot.encodedSchedules, equals(<String>[updated]));

      await store.removeByEncoded(updated);
      snapshot = await store.loadSnapshot();
      expect(snapshot.encodedSchedules, isEmpty);

      await AppStorage.instance.clear();
    });

    test(
      'imports only valid schedule payloads and verifies persistence',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{});

        final store = FriendScheduleStore();
        final encoded = _encodeSchedule(id: '20260816', name: 'QR Friend');

        await store.importPayload(encoded);
        final snapshot = await store.loadSnapshot();
        expect(snapshot.encodedSchedules, equals(<String>[encoded]));
        await expectLater(
          store.importPayload('not-a-schedule'),
          throwsA(isA<FormatException>()),
        );
        expect(
          (await store.loadSnapshot()).encodedSchedules,
          equals(<String>[encoded]),
        );

        await AppStorage.instance.clear();
      },
    );

    test('imports an exact multi-schedule export and saves metadata', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});

      final first = _encodeSchedule(id: '10001', name: 'Friend 10001');
      final second = _encodeSchedule(id: '10002', name: 'Friend 10002');
      final export = jsonEncode({
        'type': 'friend_schedules_export',
        'version': 1,
        'schedules': [first, second],
      });
      final encodedExport = base64.encode(
        GZipEncoder().encode(utf8.encode(export)),
      );
      final store = FriendScheduleStore();

      await store.importPayload(encodedExport);
      await store.saveAllMetadata({
        '10001': const FriendMetadata(
          friendId: '10001',
          nickname: 'One',
          isFavorite: true,
        ),
      });

      final snapshot = await store.loadSnapshot();
      expect(snapshot.encodedSchedules, equals(<String>[first, second]));
      expect(snapshot.metadata['10001']?.nickname, 'One');
      expect(snapshot.metadata['10001']?.isFavorite, isTrue);

      await AppStorage.instance.clear();
    });
  });
}
