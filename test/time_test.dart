import 'package:flutter_test/flutter_test.dart';
import 'package:preconnect/tools/time_utils.dart';

void main() {
  const day = [
    ('08:00 AM', '09:20 AM'),
    ('09:30 AM', '10:50 AM'),
    ('11:00 AM', '12:20 PM'),
  ];

  List<bool> outlined(DateTime now) => [
    for (final (start, end) in day)
      AppTime.isCurrentOrNextSlot(start, end, day, now: now),
  ];

  test('outlines only the running class while one is in progress', () {
    expect(outlined(DateTime(2026, 11, 9, 9, 40)), [false, true, false]);
  });

  test('outlines the next class when none is in progress', () {
    expect(outlined(DateTime(2026, 11, 9, 7, 0)), [true, false, false]);
    expect(outlined(DateTime(2026, 11, 9, 9, 25)), [false, true, false]);
  });

  test('outlines nothing after the last class ends', () {
    expect(outlined(DateTime(2026, 11, 9, 13, 0)), [false, false, false]);
  });
}
