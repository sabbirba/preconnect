import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:preconnect/api/friend_store.dart';
import 'package:preconnect/tools/app_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FriendScheduleStore', () {
    test(
      'loads modern friend_schedules_encoded_v1 and metadata_v1 keys',
      () async {
        final sampleData = jsonEncode({
          'id': '20101234',
          'name': 'Test Student',
          'courses': <Map<String, dynamic>>[],
        });
        final gzipped = GZipEncoder().encode(utf8.encode(sampleData));
        final base64Encoded = base64.encode(gzipped);

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

    test(
      'parses all schedule payload encodings (Base64+GZip, Base64, raw JSON)',
      () {
        final jsonPayload = jsonEncode({
          'id': '20261111',
          'name': 'Legacy Friend',
          'courses': <Map<String, dynamic>>[],
        });

        // Format 1: Base64 + GZip
        final gzipped = GZipEncoder().encode(utf8.encode(jsonPayload));
        final base64Gzipped = base64.encode(gzipped);
        final friend1 = FriendScheduleStore.parseSchedulePayload(base64Gzipped);
        expect(friend1?.id, equals('20261111'));
        expect(friend1?.name, equals('Legacy Friend'));

        // Format 2: Uncompressed Base64
        final base64Plain = base64.encode(utf8.encode(jsonPayload));
        final friend2 = FriendScheduleStore.parseSchedulePayload(base64Plain);
        expect(friend2?.id, equals('20261111'));
        expect(friend2?.name, equals('Legacy Friend'));

        // Format 3: Direct Raw JSON
        final friend3 = FriendScheduleStore.parseSchedulePayload(jsonPayload);
        expect(friend3?.id, equals('20261111'));
        expect(friend3?.name, equals('Legacy Friend'));
      },
    );

    test('extracts export schedules across all package encodings', () {
      final exportPackage = jsonEncode({
        'type': 'friend_schedules_export',
        'schedules': ['item1', 'item2'],
      });

      // Format 1: Base64 + GZip Export
      final gzipped = GZipEncoder().encode(utf8.encode(exportPackage));
      final base64Gzipped = base64.encode(gzipped);
      final list1 = FriendScheduleStore.extractExportSchedules(base64Gzipped);
      expect(list1, equals(['item1', 'item2']));

      // Format 2: Uncompressed Base64 Export
      final base64Plain = base64.encode(utf8.encode(exportPackage));
      final list2 = FriendScheduleStore.extractExportSchedules(base64Plain);
      expect(list2, equals(['item1', 'item2']));

      // Format 3: Direct Raw JSON Export
      final list3 = FriendScheduleStore.extractExportSchedules(exportPackage);
      expect(list3, equals(['item1', 'item2']));
    });

    test('upserts and removes schedules by id', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});

      final store = FriendScheduleStore();
      final sample = jsonEncode({
        'id': '99999',
        'name': 'Unique',
        'courses': [],
      });
      final b64 = base64.encode(GZipEncoder().encode(utf8.encode(sample)));

      await store.upsertEncodedSchedule(b64);
      var snapshot = await store.loadSnapshot();
      expect(snapshot.encodedSchedules, contains(b64));

      await store.removeByEncoded(b64);
      snapshot = await store.loadSnapshot();
      expect(snapshot.encodedSchedules, isNot(contains(b64)));

      await AppStorage.instance.clear();
    });
  });
}
