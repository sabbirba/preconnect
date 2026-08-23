import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:preconnect/api/advising_service.dart';
import 'package:preconnect/pages/advising_helper.dart';
import 'package:preconnect/tools/app_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await AppStorage.initialize();
  });

  group('AdvisingSessionInfo & AdvisingSectionRecord', () {
    test('parses active session info correctly', () {
      final json = <String, dynamic>{
        'id': '10042',
        'semesterSessionId': 20261,
        'advisingPhase': 'PHASE_TWO',
        'title': 'Spring 2026 Phase 2',
      };
      final session = AdvisingSessionInfo.fromJson(json);
      expect(session.id, '10042');
      expect(session.semesterSessionId, 20261);
      expect(session.phase, 'PHASE_TWO');
      expect(session.title, 'Spring 2026 Phase 2');
    });

    test('parses advising section record and computes remaining seats', () {
      final json = <String, dynamic>{
        'sectionId': 401,
        'advisingSectionId': 801,
        'courseId': 501,
        'courseCode': 'CSE220',
        'courseName': 'Data Structures',
        'sectionName': '01',
        'capacity': 35,
        'consumedSeat': 30,
        'courseCredit': 3,
        'faculties': 'Faculty A',
        'roomNumber': 'UB201',
      };
      final record = AdvisingSectionRecord.fromJson(json);
      expect(record.sectionId, 401);
      expect(record.advisingSectionId, 801);
      expect(record.courseCode, 'CSE220');
      expect(record.remainingSeats, 5);
    });

    test('calculates 0 remaining seats accurately', () {
      final json = <String, dynamic>{
        'sectionId': 402,
        'courseCode': 'CSE221',
        'sectionName': '02',
        'capacity': 35,
        'consumedSeat': 35,
      };
      final record = AdvisingSectionRecord.fromJson(json);
      expect(record.remainingSeats, 0);
    });
  });

  group('AdvisingAutoEngine queue and 0-seat gatekeeping', () {
    test('manages queue addition and removal', () {
      final engine = AdvisingAutoEngine();
      final item = TargetSectionItem(
        sectionId: 101,
        courseCode: 'CSE110',
        sectionName: '01',
        capacity: 30,
        consumedSeat: 30,
        courseCredit: 3,
      );

      engine.addSectionToQueue(item);
      expect(engine.targetSections.length, 1);
      expect(engine.targetSections.first.sectionId, 101);

      engine.removeSectionFromQueue(101);
      expect(engine.targetSections.isEmpty, true);
    });

    test('skips network hit if remaining seats is 0', () {
      final engine = AdvisingAutoEngine();
      final zeroSeatItem = TargetSectionItem(
        sectionId: 999,
        courseCode: 'CSE420',
        sectionName: '01',
        capacity: 30,
        consumedSeat: 30,
        courseCredit: 3,
      );

      engine.addSectionToQueue(zeroSeatItem);
      expect(zeroSeatItem.remainingSeats, 0);
      expect(zeroSeatItem.status, TargetSectionStatus.idle);
    });

    test('retains failed items in queue for continuous 1-second retries', () {
      final engine = AdvisingAutoEngine();
      final item = TargetSectionItem(
        sectionId: 500,
        courseCode: 'MAT215',
        sectionName: '06',
        capacity: 35,
        consumedSeat: 30,
        courseCredit: 3,
      );
      item.status = TargetSectionStatus.failed;
      engine.addSectionToQueue(item);

      final pending = engine.targetSections
          .where(
            (s) =>
                s.status != TargetSectionStatus.added &&
                s.status != TargetSectionStatus.adding,
          )
          .toList();

      expect(pending.length, 1);
      expect(pending.first.sectionId, 500);
    });

    test('cookie extraction builds header format', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'preconnect.cookies.connect': jsonEncode([
          {'name': 'JSESSIONID', 'value': 'test_session_123'},
          {'name': 'XSRF-TOKEN', 'value': 'xsrf_token_456'},
        ]),
      });
      await AppStorage.initialize();

      final service = AdvisingHelperService();
      final cookieHeader = await service.buildCookieHeader();
      expect(cookieHeader, contains('JSESSIONID=test_session_123'));
      expect(cookieHeader, contains('XSRF-TOKEN=xsrf_token_456'));
    });
  });

  group('AdvisingHelperPage widget test', () {
    testWidgets('renders loading state or error state gracefully', (
      tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: AdvisingHelperPage()));
      await tester.pump();

      expect(find.byType(AdvisingHelperPage), findsOneWidget);
    });
  });
}
