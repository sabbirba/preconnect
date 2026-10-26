import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:preconnect/api/extra_classes.dart';
import 'package:preconnect/model/extra_class.dart';
import 'package:preconnect/model/section_info.dart';
import 'package:preconnect/pages/alarms.dart';
import 'package:preconnect/pages/shared_widgets/entry_card.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/app_storage.dart';
import 'package:preconnect/tools/exam_visibility.dart';
import 'package:preconnect/tools/refresh_bus.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('exam focus starts at midnight three calendar days before the exam', () {
    final exam = DateTime(2030, 4, 5, 14);
    final end = DateTime(2030, 4, 5, 16);
    expect(
      ExamVisibility.isWithinReminderWindow(
        exam,
        end: end,
        now: DateTime(2030, 4, 1, 23, 59, 59),
      ),
      isFalse,
    );
    for (final now in [DateTime(2030, 4, 2), DateTime(2030, 4, 4), exam, end]) {
      expect(
        ExamVisibility.isWithinReminderWindow(exam, end: end, now: now),
        isTrue,
      );
    }
    expect(
      ExamVisibility.isWithinReminderWindow(
        exam,
        end: end,
        now: end.add(const Duration(seconds: 1)),
      ),
      isFalse,
    );
  });

  test(
    'exam focus handles a year boundary without a rolling 72-hour window',
    () {
      final exam = DateTime(2031, 1, 2, 23);
      expect(
        ExamVisibility.isWithinReminderWindow(
          exam,
          now: DateTime(2030, 12, 30),
        ),
        isTrue,
      );
      expect(
        ExamVisibility.isWithinReminderWindow(
          exam,
          now: DateTime(2030, 12, 29, 23, 59),
        ),
        isFalse,
      );
    },
  );

  testWidgets(
    'alarms include current extras with independent times and skip distant exam jumps',
    (tester) async {
      final directory = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('preconnect_alarm_'),
      ))!;
      addTearDown(() => directory.delete(recursive: true));
      final now = DateTime.now();
      Section section(int id, {int semester = 1}) => Section.fromJson({
        'sectionId': id,
        'courseCode': 'EXAMPLE',
        'sectionName': '0$id',
        'semesterSessionId': semester,
        'sectionSchedule': {
          'classEndDate': now.add(const Duration(days: 30)).toIso8601String(),
          'classSchedules': [
            {'day': 'SUNDAY', 'startTime': '08:00', 'endTime': '09:20'},
            if (id == 2)
              {'day': 'MONDAY', 'startTime': '09:30', 'endTime': '10:50'},
            if (id == 2)
              {'day': 'TUESDAY', 'startTime': '8:00 AM', 'endTime': '9:20 AM'},
          ],
        },
      });
      final examDate = now.add(const Duration(days: 5));
      SharedPreferences.setMockInitialValues({
        'currentSessionSemesterId': '1',
        'alarms_snapshot_v1': jsonEncode({
          'sections': [section(1).toJson()],
          'examEntries': [
            {
              'id': 'example-final',
              'type': 'Final',
              'courseCode': 'EXAM101',
              'sectionName': '01',
              'startTime': '14:00',
              'endTime': '16:00',
              'dateTime': DateTime(
                examDate.year,
                examDate.month,
                examDate.day,
                14,
              ).millisecondsSinceEpoch,
            },
          ],
          'customSchedules': [],
        }),
        ExtraClassesStore.storageKey: jsonEncode([
          ExtraClass(section: section(1), days: {'SUNDAY'}).toJson(),
          ExtraClass(
            section: section(2),
            days: {'SUNDAY', 'MONDAY', 'TUESDAY'},
          ).toJson(),
          ExtraClass(
            section: section(3, semester: 2),
            days: {'SUNDAY'},
          ).toJson(),
        ]),
      });
      await tester.runAsync(
        () => AppStorage.initialize(cacheDirectory: directory),
      );
      tester.view.physicalSize = const Size(500, 2200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const MaterialApp(home: AlarmPage()));
      await tester.pumpAndSettle();
      final cards = tester
          .widgetList<ScheduleEntryCard>(find.byType(ScheduleEntryCard))
          .toList();
      expect(cards, hasLength(3));
      expect(cards.where((card) => card.sectionName == '01'), hasLength(1));
      expect(
        cards
            .where((card) => card.courseType == 'Extra')
            .map((card) => card.schedule.startTime),
        ['08:00', '09:30'],
      );
      expect(cards.where((card) => card.sectionName == '03'), isEmpty);
      expect(
        find.textContaining('EXAM101', findRichText: true),
        findsOneWidget,
      );
      expect(
        tester
            .widgetList<AppCard>(find.byType(AppCard))
            .where((card) => card.isHighlighted),
        isEmpty,
      );
      expect(
        tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position
            .pixels,
        0,
      );
      final extra = find.ancestor(
        of: find.byWidgetPredicate(
          (widget) =>
              widget is ScheduleEntryCard &&
              widget.courseType == 'Extra' &&
              widget.schedule.startTime == '09:30',
        ),
        matching: find.byType(AppCard),
      );
      await tester.tap(
        find.descendant(of: extra, matching: find.byIcon(Icons.add)),
      );
      await tester.pumpAndSettle();
      expect(find.text('10 min before'), findsOneWidget);
      expect(find.text('5 min before'), findsNWidgets(2));
      await tester.runAsync(() => ExtraClassesStore().remove('1|2'));
      RefreshBus.instance.notify(reason: 'extra_classes');
      await tester.pumpAndSettle();
      expect(
        tester
            .widgetList<ScheduleEntryCard>(find.byType(ScheduleEntryCard))
            .where((card) => card.courseType == 'Extra'),
        isEmpty,
      );
      expect(find.byType(ScheduleEntryCard), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
