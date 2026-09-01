import 'package:flutter_test/flutter_test.dart';
import 'package:preconnect/model/calendar_info.dart';
import 'package:preconnect/pages/calendar.dart';
import 'package:preconnect/pages/shared_widgets/scroll_helper.dart';
import 'package:preconnect/tools/time_utils.dart';

void main() {
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

  group('BracuTime', () {
    test('parses common date formats', () {
      expect(BracuTime.parseDate('2026-02-11'), DateTime(2026, 2, 11));
      expect(BracuTime.parseDate('11/02/2026'), DateTime(2026, 2, 11));
      expect(BracuTime.parseDate('not a date'), isNull);
    });

    test('normalizes 12-hour and 24-hour times', () {
      expect(BracuTime.toMinutes('12:00 AM'), 0);
      expect(BracuTime.toMinutes('1:30 PM'), 13 * 60 + 30);
      expect(BracuTime.toMinutes('23:15'), 23 * 60 + 15);
    });

    test('maps weekday names case-insensitively', () {
      expect(BracuTime.weekdayFromName(' monday '), DateTime.monday);
      expect(BracuTime.weekdayFromName('SUNDAY'), DateTime.sunday);
      expect(BracuTime.weekdayFromName('holiday'), isNull);
      expect(BracuTime.shiftWeekday(DateTime.monday, -1), DateTime.sunday);
      expect(BracuTime.shiftWeekday(DateTime.sunday, 1), DateTime.monday);
    });

    test('formats parseable dates and preserves unknown input', () {
      expect(BracuTime.formatDate('2026-02-11'), '11 February, 2026');
      expect(BracuTime.formatDate('not a date'), 'not a date');
    });
  });
}
