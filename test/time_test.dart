import 'package:flutter_test/flutter_test.dart';
import 'package:preconnect/model/calendar_info.dart';
import 'package:preconnect/pages/calendar.dart';
import 'package:preconnect/pages/shared_widgets/scroll_helper.dart';
import 'package:preconnect/tools/time_utils.dart';

void main() {
  test('upcoming and current slots highlight until the end', () {
    for (final minute in [29, 30, 45, 59]) {
      expect(
        AppTime.isUpcomingOrCurrentSlot(
          '09:30',
          '10:00',
          now: DateTime(2026, 9, 10, 9, minute),
        ),
        isTrue,
      );
    }
    expect(
      AppTime.isUpcomingOrCurrentSlot(
        '09:30',
        '10:00',
        now: DateTime(2026, 9, 10, 10),
      ),
      isFalse,
    );
  });

  test('slot highlights support AM/PM and reject missing or invalid times', () {
    final now = DateTime(2026, 9, 10, 13);
    expect(
      AppTime.isUpcomingOrCurrentSlot('12:30 PM', '1:30 PM', now: now),
      isTrue,
    );
    expect(AppTime.isUpcomingOrCurrentSlot(null, '14:00', now: now), isFalse);
    expect(
      AppTime.isUpcomingOrCurrentSlot('invalid', '14:00', now: now),
      isFalse,
    );
    expect(
      AppTime.isUpcomingOrCurrentSlot('14:00', '12:00', now: now),
      isFalse,
    );
    expect(
      AppTime.isUpcomingOrCurrentSlot('14:00', '14:00', now: now),
      isFalse,
    );
    expect(
      AppTime.isUpcomingOrCurrentSlot('09:00', '10:00', now: now),
      isFalse,
    );
    expect(AppTime.isUpcomingOrCurrentSlot('14:00', '15:00', now: now), isTrue);
  });

  CalendarEntry event({
    required String id,
    required String date,
    required String start,
    required String end,
    bool cancelled = false,
  }) {
    return CalendarEntry(
      id: id,
      label: id,
      typeKey: 'ACADEMIC',
      date: date,
      startDate: '',
      endDate: '',
      startTime: start,
      endTime: end,
      place: '',
      isRepeatable: false,
      isCancelled: cancelled,
      ref: '',
      roomName: '',
      roomNumber: '',
      sessionLabel: '',
      building: '',
      faculty: '',
      department: '',
      actor: '',
    );
  }

  test('calendar target skips ended and cancelled events', () {
    final now = DateTime(2026, 9, 1, 12);
    final ended = event(
      id: 'ended',
      date: '2026-09-01',
      start: '9:00 AM',
      end: '10:00 AM',
    );
    final cancelled = event(
      id: 'cancelled',
      date: '2026-09-01',
      start: '12:30 PM',
      end: '1:30 PM',
      cancelled: true,
    );
    final upcoming = event(
      id: 'upcoming',
      date: '2026-09-01',
      start: '2:00 PM',
      end: '3:00 PM',
    );
    expect(
      currentOrUpcomingCalendarEntry(<CalendarEntry>[
        ended,
        cancelled,
        upcoming,
      ], now),
      upcoming,
    );
  });

  test('weekly occurrence selects ongoing, future, and next-week windows', () {
    final monday = DateTime(2026, 9, 7, 11);
    expect(
      nextWeeklyOccurrence(
        weekday: DateTime.monday,
        startMinutes: 10 * 60,
        endMinutes: 12 * 60,
        now: monday,
      ),
      monday,
    );
    expect(
      nextWeeklyOccurrence(
        weekday: DateTime.tuesday,
        startMinutes: 9 * 60,
        endMinutes: 10 * 60,
        now: monday,
      ),
      DateTime(2026, 9, 8, 9),
    );
    expect(
      nextWeeklyOccurrence(
        weekday: DateTime.monday,
        startMinutes: 9 * 60,
        endMinutes: 10 * 60,
        now: monday,
      ),
      DateTime(2026, 9, 14, 9),
    );
  });

  group('AppTime', () {
    test('parses common date formats', () {
      expect(AppTime.parseDate('2026-02-11'), DateTime(2026, 2, 11));
      expect(AppTime.parseDate('11/02/2026'), DateTime(2026, 2, 11));
      expect(AppTime.parseDate('not a date'), isNull);
    });

    test('normalizes 12-hour and 24-hour times', () {
      expect(AppTime.toMinutes('12:00 AM'), 0);
      expect(AppTime.toMinutes('1:30 PM'), 13 * 60 + 30);
      expect(AppTime.toMinutes('23:15'), 23 * 60 + 15);
    });

    test('maps weekday names case-insensitively', () {
      expect(AppTime.weekdayFromName(' monday '), DateTime.monday);
      expect(AppTime.weekdayFromName('SUNDAY'), DateTime.sunday);
      expect(AppTime.weekdayFromName('holiday'), isNull);
      expect(AppTime.shiftWeekday(DateTime.monday, -1), DateTime.sunday);
      expect(AppTime.shiftWeekday(DateTime.sunday, 1), DateTime.monday);
    });

    test('formats parseable dates and preserves unknown input', () {
      expect(AppTime.formatDate('2026-02-11'), '11 February, 2026');
      expect(AppTime.formatDate('not a date'), 'not a date');
    });
  });
}
