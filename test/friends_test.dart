import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:preconnect/model/friend_schedule.dart';
import 'package:preconnect/pages/scan_schedule.dart';

FriendSchedule _friend(String id, String name) => FriendSchedule(
  name: name,
  id: id,
  photoFilePath: null,
  photoUrl: null,
  courses: const [],
);

Future<void> _pump(
  WidgetTester tester,
  Map<String, FriendSchedule> added, {
  VoidCallback? onDone,
  VoidCallback? onScanAnother,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: FriendsAddedView(
            added: added,
            onDone: onDone ?? () {},
            onScanAnother: onScanAnother,
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('shows the card of the friend that was just added', (
    tester,
  ) async {
    var done = false;
    await _pump(tester, {
      'code-a': _friend('test-a', 'Test Student A'),
    }, onDone: () => done = true);

    expect(find.text('Schedule Added'), findsOneWidget);
    expect(find.text('Test Student A'), findsOneWidget);
    expect(find.text('No schedule shared'), findsOneWidget);
    expect(find.text('T'), findsOneWidget);
    expect(find.text('Scan Another'), findsNothing);

    await tester.tap(find.text('Done'));
    expect(done, isTrue);
  });

  testWidgets('lists every friend from a multi-friend code', (tester) async {
    var scanAgain = false;
    await _pump(tester, {
      'code-a': _friend('test-a', 'Test Student A'),
      'code-b': _friend('test-b', 'Mock Student B'),
    }, onScanAnother: () => scanAgain = true);

    expect(find.text('Schedules Added'), findsOneWidget);
    expect(find.text('Test Student A'), findsOneWidget);
    expect(find.text('Mock Student B'), findsOneWidget);

    await tester.tap(find.text('Scan Another'));
    expect(scanAgain, isTrue);
  });
}
