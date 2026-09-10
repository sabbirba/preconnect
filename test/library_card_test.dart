import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:preconnect/libsync/library_card.dart';

void main() {
  for (final width in [240.0, 280.0, 360.0, 600.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('library card fits width $width at text scale $scale', (
        tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: Scaffold(
                body: SingleChildScrollView(
                  child: SizedBox(
                    width: width,
                    child: const LibraryCard(
                      profile: {
                        'fullname': 'Example Student With A Long Display Name',
                        'department':
                            'Department of Computer Science and Engineering',
                        'student_id': 'DEMO123456',
                        'expire_date': 'September 30, 2027',
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final student = tester.getTopLeft(find.text('DEMO123456').first);
        final validity = tester.getTopLeft(find.text('September 30, 2027'));
        expect(student.dx, closeTo(validity.dx, 0.01));
        final label = tester.getTopLeft(find.text('Student ID'));
        final colons = find.text(':');
        final firstColon = tester.getTopLeft(colons.at(0));
        final secondColon = tester.getTopLeft(colons.at(1));
        expect(firstColon.dx - label.dx, closeTo(74, 0.01));
        expect(firstColon.dx, closeTo(secondColon.dx, 0.01));
        expect(
          student.dx - tester.getTopRight(colons.at(0)).dx,
          closeTo(8, 0.01),
        );
        await tester.dragFrom(const Offset(100, 200), const Offset(0, -150));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }
}
