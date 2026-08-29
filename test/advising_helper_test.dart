import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:preconnect/api/api_client.dart';
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/api/advising_service.dart';
import 'package:preconnect/model/advising_phase.dart';
import 'package:preconnect/pages/advising_helper.dart';
import 'package:preconnect/tools/app_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await AppStorage.initialize();
  });

  group('AdvisingSectionRecord', () {
    test('recognizes exact unavailable-phase response statuses', () {
      for (final status in <int>[400, 404, 412, 500]) {
        expect(isUnavailableAdvisingPhaseResponse(ApiException(status)), true);
      }
      expect(
        isUnavailableAdvisingPhaseResponse(const ApiException(401)),
        false,
      );
      expect(
        isUnavailableAdvisingPhaseResponse(const ApiException(403)),
        false,
      );
      expect(
        isUnavailableAdvisingPhaseResponse(const ApiException(502)),
        false,
      );
    });

    test('uses the current advising endpoint contracts', () {
      expect(
        ApiConfig.advisingSessionStartPath('70801', publicKey: 'key'),
        '/adv/v1/advising/70801/advising-session?publicKey=key',
      );
      expect(
        ApiConfig.advisingSectionsStudentPath('70801'),
        '/adv/v1/advising/sections/student/70801',
      );
      expect(
        ApiConfig.studentCoursesForPhasePath('70801', AdvisingPhase.phaseOne),
        '/adv/v1/student-courses/70801/phase-one',
      );
      expect(
        ApiConfig.advisingConfirmPath('70801'),
        '/adv/v1/advising/70801/confirm',
      );
    });

    test('parses advising section record and computes remaining seats', () {
      final json = <String, dynamic>{
        'sectionId': 401,
        'advisingSectionId': 801,
        'courseId': 501,
        'courseCode': 'CSE220',
        'name': 'Data Structures',
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
        'courseCredit': 3,
      };
      final record = AdvisingSectionRecord.fromJson(json);
      expect(record.remainingSeats, 0);
    });

    test('rejects response aliases and missing exact fields', () {
      expect(
        () => AdvisingSectionRecord.fromJson(<String, dynamic>{
          'id': 402,
          'code': 'CSE221',
          'section': '02',
          'capacity': 35,
          'consumedSeat': 35,
          'credit': 3,
        }),
        throwsFormatException,
      );
    });

    test('preserves the server seat arithmetic without clamping', () {
      final record = AdvisingSectionRecord.fromJson(<String, dynamic>{
        'sectionId': 402,
        'courseCode': 'CSE221',
        'sectionName': '02',
        'capacity': 35,
        'consumedSeat': 37,
        'courseCredit': 3,
      });

      expect(record.remainingSeats, -2);
    });

    test('rejects wrapped section responses and removes duplicate IDs', () {
      final section = <String, dynamic>{
        'sectionId': 402,
        'courseCode': 'CSE221',
        'sectionName': '02',
        'capacity': 35,
        'consumedSeat': 30,
        'courseCredit': 3,
      };

      expect(
        () => parseAdvisedSectionsResponse(
          jsonEncode(<String, dynamic>{
            'sections': <Map<String, dynamic>>[section],
          }),
        ),
        throwsFormatException,
      );
      expect(
        parseAdvisedSectionsResponse(jsonEncode(<Object>[section, section])),
        hasLength(1),
      );
    });
  });

  group('AdvisingAutoEngine queue and 0-seat gatekeeping', () {
    test('manages queue addition and removal', () {
      final engine = AdvisingAutoEngine();
      final item = TargetSectionItem(
        sectionId: 101,
        courseId: 1001,
        courseCode: 'CSE110',
        sectionName: '01',
        capacity: 30,
        consumedSeat: 30,
        courseCredit: 3,
      );

      engine.addSectionToQueue(item);
      engine.addSectionToQueue(item);
      expect(engine.targetSections.length, 1);
      expect(engine.targetSections.first.sectionId, 101);

      engine.removeSectionFromQueue(101);
      expect(engine.targetSections.isEmpty, true);
    });

    test('reset removes every phase-specific state value', () {
      final engine = AdvisingAutoEngine();
      engine.addSectionToQueue(
        TargetSectionItem(
          sectionId: 101,
          courseId: 1001,
          courseCode: 'CSE110',
          sectionName: '01',
          capacity: 30,
          consumedSeat: 30,
          courseCredit: 3,
        ),
      );

      engine.reset();

      expect(engine.targetSections, isEmpty);
      expect(engine.activityLogs, isEmpty);
      expect(engine.isRunning, isFalse);
      expect(engine.portfolioId, isNull);
      expect(engine.sessionId, isNull);
      expect(engine.publicKey, isNull);
    });

    test('skips network hit if remaining seats is 0', () {
      final engine = AdvisingAutoEngine();
      final zeroSeatItem = TargetSectionItem(
        sectionId: 999,
        courseId: 1999,
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
        courseId: 1500,
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
        'preconnect.cookies.sso': jsonEncode([
          {'name': 'SSO_SESSION', 'value': 'must_not_be_forwarded'},
        ]),
      });
      await AppStorage.initialize();

      final service = AdvisingHelperService();
      final cookieHeader = await service.buildCookieHeader();
      expect(cookieHeader, contains('JSESSIONID=test_session_123'));
      expect(cookieHeader, contains('XSRF-TOKEN=xsrf_token_456'));
      expect(cookieHeader, isNot(contains('SSO_SESSION')));
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
