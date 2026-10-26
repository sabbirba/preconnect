import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:preconnect/pages/ui_kit.dart';

void main() {
  for (final dayCount in [30, 10]) {
    testWidgets('date picker offers $dayCount days including today', (
      tester,
    ) async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final lastDate = DateTime(now.year, now.month, now.day + dayCount - 1);
      DateTime? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  selected = await showAppDatePicker(
                    context,
                    initialDate: today,
                    dayCount: dayCount,
                  );
                },
                child: const Text('Choose Date'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Choose Date'));
      await tester.pumpAndSettle();
      expect(
        find.text('Today - ${DateFormat('d MMMM yyyy').format(today)}'),
        findsOneWidget,
      );
      final list = find.byType(ListView);
      final delegate = tester.widget<ListView>(list).childrenDelegate;
      expect(delegate.estimatedChildCount, dayCount);
      final lastLabel = DateFormat('EEEE, d MMMM yyyy').format(lastDate);
      await tester.scrollUntilVisible(
        find.text(lastLabel),
        250,
        scrollable: find.descendant(
          of: list,
          matching: find.byType(Scrollable),
        ),
      );
      await tester.tap(find.text(lastLabel));
      await tester.pumpAndSettle();
      expect(selected, lastDate);
    });
  }
}
