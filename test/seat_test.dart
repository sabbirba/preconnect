import 'package:flutter_test/flutter_test.dart';
import 'package:preconnect/api/seat_status.dart';
import 'package:preconnect/model/seat_timetable.dart';
import 'package:preconnect/pages/shared_widgets/routine_sheet.dart';
import 'package:preconnect/pages/shared_widgets/seat_card.dart';
import 'package:preconnect/pages/shared_widgets/seat_filters.dart';

bool matchesAvailable(int remaining) {
  return matchesSeatFilters(
    availableOnly: true,
    remaining: remaining,
    mode: '',
    hasLabSection: false,
    theorySchedules: const [],
    labSchedules: const [],
    day: '',
    time: const SeatTimetable(startTime: '', endTime: ''),
  );
}

void main() {
  test('available filter keeps only sections with open seats', () {
    expect(matchesAvailable(-2), isFalse);
    expect(matchesAvailable(0), isFalse);
    expect(matchesAvailable(1), isTrue);
  });

  test('update sort cycles normal, latest, oldest like the web', () {
    expect(nextSeatUpdateSort(''), 'Latest');
    expect(nextSeatUpdateSort('Latest'), 'Oldest');
    expect(nextSeatUpdateSort('Oldest'), '');
  });

  test('seat trend reads the feed trend before the delta', () {
    expect(seatTrendOf('UP', -3), 'up');
    expect(seatTrendOf(null, 2), 'up');
    expect(seatTrendOf('flat', -1), 'down');
    expect(seatTrendOf(null, 0), '');
  });

  test('seat updated text matches the web wording', () {
    final now = DateTime(2026, 11, 8, 12);
    String ago(Duration elapsed) => seatUpdatedAgo(now.subtract(elapsed), now);
    expect(ago(Duration.zero), '1 second ago');
    expect(ago(const Duration(seconds: 42)), '42 seconds ago');
    expect(ago(const Duration(minutes: 1)), '1 minute ago');
    expect(ago(const Duration(hours: 3)), '3 hours ago');
    expect(ago(const Duration(hours: 2, minutes: 5)), '2 hours 5 minutes ago');
    expect(ago(const Duration(days: 2, hours: 1)), '2 days 1 hour ago');
  });

  test('planner schedule dates start from today', () {
    final sunday = DateTime(2026, 11, 8, 15);
    expect(nextDateForWeekday('SUNDAY', sunday), DateTime(2026, 11, 8));
    expect(nextDateForWeekday('TUESDAY', sunday), DateTime(2026, 11, 10));
    expect(nextDateForWeekday('SATURDAY', sunday), DateTime(2026, 11, 14));
  });

  test('section keeps update time and trend through a round trip', () {
    final parsed = SeatStatusDetailsResponse.fromJson({
      'sectionId': 1,
      'lastUpdatedAt': '2026-10-18T07:19:11.374Z',
      'seatDelta': 1,
      'seatTrend': 'up',
    });
    final again = SeatStatusDetailsResponse.fromJson(parsed.toJson());
    expect(
      again.lastUpdatedAt?.toUtc(),
      DateTime.utc(2026, 10, 18, 7, 19, 11, 374),
    );
    expect(again.seatDelta, 1);
    expect(SeatCardData.fromDetails(again).seatTrend, 'up');
  });
}
