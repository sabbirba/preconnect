import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/holiday.dart';

void main() {
  testWidgets('GitHub icon keeps its requested size in a tight layout', (
    tester,
  ) async {
    const iconKey = Key('github-icon');
    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(
          width: 120,
          height: 48,
          child: PreConnectGitHubIcon(key: iconKey, size: 24),
        ),
      ),
    );

    final iconPaint = find.descendant(
      of: find.byKey(iconKey),
      matching: find.byType(CustomPaint),
    );
    final customPaint = tester.widget<CustomPaint>(iconPaint);
    expect(customPaint.size, const Size.square(24));
    expect(tester.getSize(iconPaint), const Size.square(24));
  });

  test('today schedule status resolves shared holiday and empty values', () {
    const holiday = HolidayStatus(
      isTodayHoliday: true,
      todayHolidayNames: <String>['National Day'],
      nextHolidaysThisYear: <HolidayItem>[],
    );

    final holidayStatus = BracuTodayScheduleStatus.resolve(
      holidayStatus: holiday,
    );
    final emptyStatus = BracuTodayScheduleStatus.resolve(
      holidayStatus: HolidayStatus.empty,
    );

    expect(holidayStatus.badge, 'OFF');
    expect(holidayStatus.title, 'National holiday');
    expect(holidayStatus.subtitle, 'National Day');
    expect(emptyStatus.badge, '--');
    expect(emptyStatus.title, 'No Classes Today');
    expect(emptyStatus.subtitle, 'Enjoy your day off.');
    expect(formatSectionBadge('OFF'), 'OFF');
    expect(formatSectionBadge('off'), 'OFF');
  });
}
