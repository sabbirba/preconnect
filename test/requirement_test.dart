import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:preconnect/model/progress_info.dart';
import 'package:preconnect/pages/requirement_courses.dart';
import 'package:shared_preferences/shared_preferences.dart';

ProgressInfo _info(Map<String, bool> mandatoryByCode) {
  return ProgressInfo.fromPayload(<String, dynamic>{
    'curriculum': <String, dynamic>{
      'name': 'Sample Program',
      'totalCredit': 9,
      'headerCreditRequirements': <Map<String, dynamic>>[
        <String, dynamic>{
          'name': 'General Education',
          'minimumCreditRequired': 9,
          'subHeaderCreditRequirements': <Map<String, dynamic>>[
            <String, dynamic>{
              'name': 'Core',
              'curriculumCourses': <Map<String, dynamic>>[
                for (final entry in mandatoryByCode.entries)
                  <String, dynamic>{
                    'courseCode': entry.key,
                    'courseName': 'Sample course',
                    'courseCredit': 3,
                    'isMandatory': entry.value,
                  },
              ],
            },
          ],
        },
      ],
    },
    'completedCourses': const <Map<String, dynamic>>[],
    'majorMinors': const <Map<String, dynamic>>[],
  });
}

Future<void> _openPage(WidgetTester tester, ProgressInfo info) async {
  await tester.pumpWidget(
    MaterialApp(
      home: RequirementCoursesPage(
        info: info,
        headerTitle: 'General Education',
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _selectFilter(WidgetTester tester, String label) async {
  await tester.tap(find.byIcon(Icons.filter_list_rounded));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  final mixed = <String, bool>{'REQ101': true, 'OPT201': false, 'REQ102': true};

  testWidgets('shows required and optional courses by default', (tester) async {
    await _openPage(tester, _info(mixed));

    expect(find.textContaining('REQ101'), findsOneWidget);
    expect(find.textContaining('REQ102'), findsOneWidget);
    expect(find.textContaining('OPT201'), findsOneWidget);
  });

  testWidgets('Required Only hides optional courses', (tester) async {
    await _openPage(tester, _info(mixed));
    await _selectFilter(tester, 'Required Only');

    expect(find.textContaining('REQ101'), findsOneWidget);
    expect(find.textContaining('REQ102'), findsOneWidget);
    expect(find.textContaining('OPT201'), findsNothing);
  });

  testWidgets('Optional Only hides required courses', (tester) async {
    await _openPage(tester, _info(mixed));
    await _selectFilter(tester, 'Optional Only');

    expect(find.textContaining('OPT201'), findsOneWidget);
    expect(find.textContaining('REQ101'), findsNothing);
    expect(find.textContaining('REQ102'), findsNothing);
  });

  testWidgets('All Courses restores the full list', (tester) async {
    await _openPage(tester, _info(mixed));
    await _selectFilter(tester, 'Optional Only');
    await _selectFilter(tester, 'All Courses');

    expect(find.textContaining('REQ101'), findsOneWidget);
    expect(find.textContaining('OPT201'), findsOneWidget);
  });

  testWidgets('shows an empty message when no course matches the filter', (
    tester,
  ) async {
    await _openPage(tester, _info(<String, bool>{'REQ101': true}));
    await _selectFilter(tester, 'Optional Only');

    expect(find.textContaining('REQ101'), findsNothing);
    expect(
      find.text('No optional courses found for this section.'),
      findsOneWidget,
    );
  });
}
