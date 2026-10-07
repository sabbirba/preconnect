import 'package:flutter_test/flutter_test.dart';
import 'package:preconnect/tools/holiday.dart';

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
}
