import 'package:flutter_test/flutter_test.dart';
import 'package:preconnect/tools/time_utils.dart';

void main() {
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
