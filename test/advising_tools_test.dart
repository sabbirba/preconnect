import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:preconnect/api/schedule.dart';
import 'package:preconnect/model/advising_phase.dart';
import 'package:preconnect/model/section_info.dart';
import 'package:preconnect/pages/advising_phase.dart';
import 'package:preconnect/pages/lab_sections.dart';

void main() {
  testWidgets('advising page surfaces a missing student profile', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AdvisingPhasePage(
          phase: AdvisingPhase.phaseOne,
          loadSections: (_, {forceRefresh = false}) async {
            throw const StudentPortfolioUnavailableException();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Student profile is unavailable'), findsOne);
    expect(find.textContaining('No registered courses'), findsNothing);
  });

  testWidgets('lab sections load tabs lazily', (tester) async {
    final calls = <String>[];
    Future<List<Section>> load(
      String phase, {
      bool forceRefresh = false,
    }) async {
      calls.add(phase);
      return const <Section>[];
    }

    await tester.pumpWidget(
      MaterialApp(home: LabSectionsPage(loadSections: load)),
    );
    await tester.pumpAndSettle();

    expect(calls, <String>['PHASE_ONE']);

    await tester.tap(find.text('Phase 2'));
    await tester.pumpAndSettle();

    expect(calls, <String>['PHASE_ONE', 'PHASE_TWO']);
  });
}
