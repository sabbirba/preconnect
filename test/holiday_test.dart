import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:preconnect/api/api_client.dart';
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/tools/app_storage.dart';
import 'package:preconnect/tools/holiday.dart';
import 'package:preconnect/tools/ramadan.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _isoDaysFromToday(int days) =>
    HolidayTiming.toIsoDate(DateTime.now().add(Duration(days: days)));

String _staleHolidaySnapshot() {
  final yesterday = _isoDaysFromToday(-1);
  return jsonEncode({
    'isTodayHoliday': true,
    'todayHolidayNames': ['Yesterday Holiday'],
    'nextHolidaysThisYear': [
      {
        'startDate': yesterday,
        'endDate': yesterday,
        'label': 'Yesterday Holiday',
      },
    ],
    'allHolidays': [
      {
        'startDate': yesterday,
        'endDate': yesterday,
        'label': 'Yesterday Holiday',
      },
    ],
  });
}

void _serve(Map<String, http.Response Function()> routes) {
  ApiClient.testOverride = ApiClient.testing(
    MockClient((request) async {
      final route = routes[request.url.toString()];
      return route == null ? http.Response('', 404) : route();
    }),
  );
}

void main() {
  group('HolidayStatus academic off day detection', () {
    test('identifies university closed and holiday events', () {
      expect(
        HolidayStatus.isAcademicOffDay('Shab-E-Barat* -University closed'),
        isTrue,
      );
      expect(
        HolidayStatus.isAcademicOffDay('Eid-ul-Fitr* - University closed'),
        isTrue,
      );
      expect(
        HolidayStatus.isAcademicOffDay('Independence Day - University closed'),
        isTrue,
      );
      expect(
        HolidayStatus.isAcademicOffDay(
          'Durga Puja (Bijoya Dashami) - University Closed',
        ),
        isTrue,
      );
      expect(HolidayStatus.isAcademicOffDay('Eid-ul-Adha*'), isTrue);
      expect(
        HolidayStatus.isAcademicOffDay(
          'July Mass Uprising Day (University Closed)',
        ),
        isTrue,
      );
      expect(
        HolidayStatus.isAcademicOffDay('Ashura (Muharram)*-University closed'),
        isTrue,
      );
      expect(
        HolidayStatus.isAcademicOffDay('Janmastami (University Closed)'),
        isTrue,
      );
      expect(
        HolidayStatus.isAcademicOffDay('Naba Barsha - University Closed'),
        isTrue,
      );
    });

    test('rejects regular academic events', () {
      expect(
        HolidayStatus.isAcademicOffDay('Classes of Spring 2026 Begin'),
        isFalse,
      );
      expect(
        HolidayStatus.isAcademicOffDay('Payment for Spring 2026'),
        isFalse,
      );
      expect(
        HolidayStatus.isAcademicOffDay('Self Registration, Spring 2026'),
        isFalse,
      );
      expect(HolidayStatus.isAcademicOffDay('Mid-Term Exams week'), isFalse);
      expect(HolidayStatus.isAcademicOffDay('Final Examinations'), isFalse);
    });

    test('cleans off day labels properly', () {
      expect(
        HolidayStatus.cleanOffDayLabel('Shab-E-Barat* -University closed'),
        'Shab-E-Barat',
      );
      expect(
        HolidayStatus.cleanOffDayLabel('Eid-ul-Fitr* - University closed'),
        'Eid-ul-Fitr',
      );
      expect(
        HolidayStatus.cleanOffDayLabel(
          'Durga Puja (Bijoya Dashami) - University Closed',
        ),
        'Durga Puja (Bijoya Dashami)',
      );
      expect(HolidayStatus.cleanOffDayLabel('Eid-ul-Adha*'), 'Eid-ul-Adha');
      expect(
        HolidayStatus.cleanOffDayLabel(
          'July Mass Uprising Day (University Closed)',
        ),
        'July Mass Uprising Day',
      );
      expect(
        HolidayStatus.cleanOffDayLabel('University closed'),
        'University Holiday',
      );
      expect(
        HolidayStatus.cleanOffDayLabel('University Closed - Shab-E-Barat'),
        'Shab-E-Barat',
      );
    });

    test('resolves dates within holiday ranges', () {
      final status = HolidayStatus(
        isTodayHoliday: false,
        todayHolidayNames: const <String>[],
        nextHolidaysThisYear: const <HolidayItem>[
          (
            startDate: '2026-03-18',
            endDate: '2026-03-25',
            label: 'Eid-ul-Fitr',
          ),
          (
            startDate: '2026-03-26',
            endDate: '2026-03-26',
            label: 'Independence Day',
          ),
        ],
        allHolidays: const <HolidayItem>[
          (
            startDate: '2026-03-18',
            endDate: '2026-03-25',
            label: 'Eid-ul-Fitr',
          ),
          (
            startDate: '2026-03-26',
            endDate: '2026-03-26',
            label: 'Independence Day',
          ),
        ],
      );

      expect(status.isHolidayOn(DateTime(2026, 3, 18)), isTrue);
      expect(status.holidayNameOn(DateTime(2026, 3, 18)), 'Eid-ul-Fitr');
      expect(status.isHolidayOn(DateTime(2026, 3, 22)), isTrue);
      expect(status.holidayNameOn(DateTime(2026, 3, 22)), 'Eid-ul-Fitr');
      expect(status.isHolidayOn(DateTime(2026, 3, 25)), isTrue);
      expect(status.isHolidayOn(DateTime(2026, 3, 26)), isTrue);
      expect(status.holidayNameOn(DateTime(2026, 3, 26)), 'Independence Day');

      expect(status.isHolidayOn(DateTime(2026, 3, 17)), isFalse);
      expect(status.holidayNameOn(DateTime(2026, 3, 17)), isNull);
      expect(status.isHolidayOn(DateTime(2026, 3, 27)), isFalse);
    });

    test('applies the today holiday flag only to today', () {
      const status = HolidayStatus(
        isTodayHoliday: true,
        todayHolidayNames: <String>[],
        nextHolidaysThisYear: <HolidayItem>[],
      );
      final now = DateTime.now();

      expect(status.isHolidayOn(now), isTrue);
      expect(
        status.isHolidayOn(DateTime(now.year, now.month, now.day + 1)),
        isFalse,
      );
    });

    test('deduplicates overlapping holiday labels on same date', () {
      final status = HolidayStatus(
        isTodayHoliday: false,
        todayHolidayNames: const <String>[],
        nextHolidaysThisYear: const <HolidayItem>[],
        allHolidays: const <HolidayItem>[
          (startDate: '2026-10-20', endDate: '2026-10-22', label: 'Durga Puja'),
          (
            startDate: '2026-10-20',
            endDate: '2026-10-22',
            label: 'Durga Puja (Bijoya Dashami)',
          ),
        ],
      );

      expect(status.isHolidayOn(DateTime(2026, 10, 20)), isTrue);
      expect(status.holidayNameOn(DateTime(2026, 10, 20)), 'Durga Puja');
    });

    test('roundtrips cache serialization', () {
      final status = HolidayStatus(
        isTodayHoliday: true,
        todayHolidayNames: const <String>['Shab-E-Barat'],
        nextHolidaysThisYear: const <HolidayItem>[
          (
            startDate: '2026-02-04',
            endDate: '2026-02-04',
            label: 'Shab-E-Barat',
          ),
        ],
        allHolidays: const <HolidayItem>[
          (
            startDate: '2026-02-04',
            endDate: '2026-02-04',
            label: 'Shab-E-Barat',
          ),
        ],
      );

      final cached = status.toCacheJson();
      final restored = HolidayStatus.fromCache(cached);

      expect(restored.isTodayHoliday, isTrue);
      expect(restored.todayHolidayNames, ['Shab-E-Barat']);
      expect(restored.allHolidays.length, 1);
      expect(restored.isHolidayOn(DateTime(2026, 2, 4)), isTrue);
    });

    test('formats iso date correctly', () {
      expect(HolidayTiming.toIsoDate(DateTime(2026, 2, 4)), '2026-02-04');
      expect(HolidayTiming.toIsoDate(DateTime(2026, 12, 16)), '2026-12-16');
    });
  });

  group('Live holiday and Ramadan status', () {
    late Directory directory;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('preconnect_holiday_');
      SharedPreferences.setMockInitialValues({});
      await AppStorage.initialize(cacheDirectory: directory);
      HolidayTiming.resetSession();
    });

    tearDown(() async {
      ApiClient.testOverride = null;
      HolidayTiming.resetSession();
      await directory.delete(recursive: true);
    });

    test(
      'cold start prefers the network over a stale holiday snapshot',
      () async {
        await AppStorage.instance.setString(
          'holiday_status_v1',
          _staleHolidaySnapshot(),
        );
        await AppStorage.instance.setString(
          'holiday_payload_v1',
          _staleHolidaySnapshot(),
        );
        final upcoming = _isoDaysFromToday(3);
        _serve({
          ApiConfig.holidayStatusUrl: () => http.Response(
            jsonEncode([
              {
                'startDate': upcoming,
                'endDate': upcoming,
                'label': 'Victory Day',
              },
            ]),
            200,
          ),
        });

        expect(HolidayTiming.cachedStatus.isTodayHoliday, isFalse);
        final status = await HolidayTiming.getTodayStatus();

        expect(status.isTodayHoliday, isFalse);
        expect(status.todayHolidayNames, isEmpty);
        expect(status.nextHolidaysThisYear.map((item) => item.label), [
          'Victory Day',
        ]);
      },
    );

    test(
      'offline holiday status rebases the saved snapshot to today',
      () async {
        await AppStorage.instance.setString(
          'holiday_status_v1',
          _staleHolidaySnapshot(),
        );
        _serve({
          ApiConfig.holidayStatusUrl: () =>
              throw const SocketException('offline'),
        });

        final status = await HolidayTiming.getTodayStatus();

        expect(status.isTodayHoliday, isFalse);
        expect(status.todayHolidayNames, isEmpty);
        expect(status.allHolidays.map((item) => item.label), [
          'Yesterday Holiday',
        ]);
        expect(HolidayTiming.cachedStatus.isTodayHoliday, isFalse);
      },
    );

    test(
      'offline holiday status keeps a saved holiday covering today',
      () async {
        final today = _isoDaysFromToday(0);
        await AppStorage.instance.setString(
          'holiday_status_v1',
          jsonEncode({
            'isTodayHoliday': false,
            'todayHolidayNames': <String>[],
            'nextHolidaysThisYear': [
              {'startDate': today, 'endDate': today, 'label': 'Today Holiday'},
            ],
          }),
        );
        _serve({});

        final status = await HolidayTiming.getTodayStatus();

        expect(status.isTodayHoliday, isTrue);
        expect(status.todayHolidayNames, ['Today Holiday']);
      },
    );

    test(
      'cold start prefers the network over a stale Ramadan payload',
      () async {
        await AppStorage.instance.setString(
          'ramadan_status_v1',
          jsonEncode({'isRamadan': true, 'ramadanDay': 12}),
        );
        _serve({
          ApiConfig.ramadanStatusUrl: () =>
              http.Response(jsonEncode({'isRamadan': false}), 200),
        });

        final status = await RamadanTiming.getRamadanStatus();

        expect(status.isRamadan, isFalse);
        expect(status.ramadanDay, isNull);
      },
    );

    test('offline Ramadan status ignores saved payloads', () async {
      await AppStorage.instance.setString(
        'ramadan_status_v1',
        jsonEncode({'isRamadan': true, 'ramadanDay': 12}),
      );
      _serve({});

      final status = await RamadanTiming.getRamadanStatus(forceRefresh: true);
      expect(status.isRamadan, isFalse);
      expect(status.ramadanDay, isNull);
    });
  });
}
