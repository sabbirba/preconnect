import 'package:flutter_test/flutter_test.dart';
import 'package:preconnect/features/schedule/application/today_widget.dart';

void main() {
  test('day keys are year, month and day digits', () {
    expect(TodayWidget.dayKey(DateTime(2026, 11, 12, 23, 59)), 20261112);
    expect(TodayWidget.dayKey(DateTime(2027, 1, 3)), 20270103);
  });

  test('widget days round trip through json', () {
    const day = TodayWidgetData(
      day: 20261112,
      title: 'Today is Thursday',
      date: '12 November, 2026',
      items: [
        TodayItem(
          badge: '01',
          title: 'CSE320',
          subtitle: '2:00 PM - 3:20 PM',
          trailing: '09H-33C',
          trailingSub: 'MSAH',
          startMinutes: 840,
          endMinutes: 920,
        ),
        TodayItem(badge: 'OFF', title: 'University Holiday', subtitle: 'Eid'),
      ],
    );

    final restored = TodayWidgetData.fromJson(day.toJson());

    expect(restored.day, 20261112);
    expect(restored.title, 'Today is Thursday');
    expect(restored.date, '12 November, 2026');
    expect(restored.items.first.toJson(), day.items.first.toJson());
    expect(restored.items.last.startMinutes, -1);
    expect(restored.items.last.endMinutes, -1);
  });
}
