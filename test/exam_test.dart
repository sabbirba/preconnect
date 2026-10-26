import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:preconnect/pages/exam_schedule.dart';
import 'package:preconnect/pages/shared_widgets/exam_card.dart';
import 'package:preconnect/tools/app_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('exam types use compact date labels without group headings', (
    tester,
  ) async {
    final directory = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('preconnect_exam_'),
    ))!;
    addTearDown(() => directory.delete(recursive: true));
    final now = DateTime.now();
    SharedPreferences.setMockInitialValues({
      'currentSessionSemesterId': '1',
      'student_schedule_v1_1': jsonEncode([
        for (final id in [1, 2])
          {
            'sectionId': id,
            'courseCode': 'EXAMPLE$id',
            'sectionName': '01',
            'semesterSessionId': 1,
            'sectionSchedule': {
              'midExamDate': now.add(const Duration(days: 2)).toIso8601String(),
              'midExamStartTime': '08:00',
              'midExamEndTime': '10:00',
              'finalExamDate': now
                  .add(const Duration(days: 30))
                  .toIso8601String(),
              'finalExamStartTime': '08:00',
              'finalExamEndTime': '10:00',
            },
          },
      ]),
      'student_semester_sessions_v1': jsonEncode([
        {'semesterSessionId': 1, 'description': 'Example Semester'},
      ]),
      'student_semester_sessions_v1_fetched_at': now.millisecondsSinceEpoch
          .toString(),
    });
    await tester.runAsync(
      () => AppStorage.initialize(cacheDirectory: directory),
    );
    tester.view.physicalSize = const Size(500, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: ExamSchedule()));
    await tester.pumpAndSettle();
    expect(find.text('Midterm'), findsNWidgets(2));
    expect(tester.widget<Text>(find.text('Midterm').first).style?.fontSize, 12);
    expect(find.byType(ExamCard), findsNWidgets(4));
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
