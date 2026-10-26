import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:preconnect/api/extra_classes.dart';
import 'package:preconnect/model/extra_class.dart';
import 'package:preconnect/model/section_info.dart';
import 'package:preconnect/pages/extra_classes.dart';
import 'package:preconnect/pages/class_schedule.dart';
import 'package:preconnect/pages/shared_widgets/entry_card.dart';
import 'package:preconnect/pages/shared_widgets/exam_card.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/app_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

Section sampleSection(
  int id, {
  int semester = 1,
  String startDate = '',
  String endDate = '',
}) => Section.fromJson({
  'sectionId': id,
  'courseCode': 'EXAMPLE$id',
  'sectionName': '01',
  'semesterSessionId': semester,
  'studentPortfolioId': 999,
  'roomNumber': 'Example Room',
  'sectionSchedule': {
    'classStartDate': startDate,
    'classEndDate': endDate,
    'midExamDate': '2030-05-01',
    'classSchedules': [
      {'day': 'SUNDAY', 'startTime': '08:00:00', 'endTime': '09:20:00'},
      {'day': 'MONDAY', 'startTime': '09:30:00', 'endTime': '10:50:00'},
    ],
  },
});

class _RejectingStore extends InMemorySharedPreferencesStore {
  _RejectingStore() : super.empty();

  @override
  Future<bool> setValue(String valueType, String key, Object value) async =>
      false;
}

class _MemoryExtras extends ExtraClassesStore {
  _MemoryExtras([this.items = const []]);
  List<ExtraClass> items;

  @override
  Future<List<ExtraClass>> load() async => items;

  @override
  Future<void> save(ExtraClass item) async {
    items = [...items.where((existing) => existing.key != item.key), item];
  }

  @override
  Future<void> remove(String key) async {
    items = items.where((item) => item.key != key).toList();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  final store = ExtraClassesStore();

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('preconnect_extra_');
    SharedPreferences.setMockInitialValues({});
    await AppStorage.initialize(cacheDirectory: directory);
  });

  tearDown(() async => directory.delete(recursive: true));

  test(
    'selected days survive restart while all days remain editable',
    () async {
      final section = sampleSection(1);
      await store.save(ExtraClass(section: section, days: {'sunday'}));
      await AppStorage.initialize(cacheDirectory: directory);
      final saved = (await store.load()).single;
      expect(saved.days, {'SUNDAY'});
      await store.save(ExtraClass(section: saved.section, days: {'MONDAY'}));
      expect((await store.load()).single.days, {'MONDAY'});
    },
  );

  test(
    'overlapping saves from separate stores preserve both selections',
    () async {
      final first = ExtraClass(section: sampleSection(1), days: {'SUNDAY'});
      final second = ExtraClass(
        section: sampleSection(2, semester: 2),
        days: {'MONDAY'},
      );
      await Future.wait([store.save(first), ExtraClassesStore().save(second)]);
      expect(await store.load(), hasLength(2));
      await store.remove(first.key);
      expect((await store.load()).single.key, second.key);
    },
  );

  test('invalid selections cannot replace saved classes', () async {
    await store.save(ExtraClass(section: sampleSection(1), days: {'SUNDAY'}));
    for (final days in [
      <String>{},
      {'FRIDAY'},
      {'INVALID'},
    ]) {
      await expectLater(
        store.save(ExtraClass(section: sampleSection(1), days: days)),
        throwsArgumentError,
      );
    }
    expect((await store.load()).single.days, {'SUNDAY'});
  });

  test('rejected persistence fails visibly and leaves storage empty', () async {
    SharedPreferencesStorePlatform.instance = _RejectingStore();
    SharedPreferences.resetStatic();
    await AppStorage.initialize(cacheDirectory: directory);
    await expectLater(
      store.save(ExtraClass(section: sampleSection(1), days: {'SUNDAY'})),
      throwsStateError,
    );
    expect(await store.load(), isEmpty);
  });

  test(
    'damaged saved selections are surfaced and never silently overwritten',
    () async {
      await AppStorage.instance.setString(
        ExtraClassesStore.storageKey,
        'invalid',
      );
      await expectLater(store.load(), throwsFormatException);
      await expectLater(
        store.save(ExtraClass(section: sampleSection(1), days: {'SUNDAY'})),
        throwsFormatException,
      );
      expect(
        await AppStorage.instance.getString(ExtraClassesStore.storageKey),
        'invalid',
      );
    },
  );

  test(
    'clearing account storage removes extra classes without a stale cache',
    () async {
      await store.save(ExtraClass(section: sampleSection(1), days: {'SUNDAY'}));
      await AppStorage.instance.clear();
      expect(await store.load(), isEmpty);
    },
  );

  for (final matching in [true, false]) {
    testWidgets(
      'extra classes ${matching ? 'join matching' : 'retain different'} times within each section',
      (tester) async {
        tester.view.physicalSize = const Size(320, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final data = sampleSection(2).toJson();
        final schedule = Map<String, dynamic>.from(
          data['sectionSchedule'] as Map,
        );
        schedule['classSchedules'] = [
          {'day': 'SUNDAY', 'startTime': '08:00:00', 'endTime': '09:20:00'},
          {
            'day': 'MONDAY',
            'startTime': matching ? '8:00 AM' : '09:30:00',
            'endTime': matching ? '9:20 AM' : '10:50:00',
          },
        ];
        data['sectionSchedule'] = schedule;
        final section = Section.fromJson(data);
        final other = Section.fromJson({
          ...data,
          'sectionId': 3,
          'sectionName': '02',
        });
        final memoryStore = _MemoryExtras();
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(
              brightness: matching ? Brightness.dark : Brightness.light,
            ),
            home: ExtraClassesPage(
              semesterSessionId: 1,
              officialSections: const [],
              isRamadan: false,
              store: memoryStore,
              loadSections: () async => [section, other],
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(ScheduleEntryCard), findsNWidgets(matching ? 2 : 4));
        final search = tester.getRect(find.byType(AppSearchField));
        final card = tester.getRect(find.byType(AppCard).first);
        expect(card.left, search.left);
        await tester.tap(find.byTooltip('Help'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Local Routine'),
          180,
          scrollable: find
              .descendant(
                of: find.byType(BottomSheet),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(Icons.close_rounded));
        await tester.pumpAndSettle();

        await tester.tap(find.byTooltip('Add Classes').first);
        await tester.pumpAndSettle();
      },
    );
  }

  testWidgets(
    'extra classes add and remove directly without editors or conflict messages',
    (tester) async {
      final memoryStore = _MemoryExtras();
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: ExtraClassesPage(
            store: memoryStore,
            semesterSessionId: 1,
            officialSections: [sampleSection(1)],
            isRamadan: false,
            loadSections: () async => [
              sampleSection(1),
              sampleSection(2),
              sampleSection(3, semester: 2),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('EXAMPLE3 Section 01'), findsNothing);
      await tester.tap(find.byTooltip('Add Classes'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Remove Classes'));
      await tester.pumpAndSettle();
    },
  );

  testWidgets('saved classes can be removed when catalogue loading fails', (
    tester,
  ) async {
    final memoryStore = _MemoryExtras([
      ExtraClass(section: sampleSection(2), days: {'SUNDAY'}),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        home: ExtraClassesPage(
          store: memoryStore,
          semesterSessionId: 1,
          officialSections: const [],
          isRamadan: false,
          loadSections: () async => throw const SocketException('offline'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('Remove Classes'), findsOneWidget);
    await tester.tap(find.byTooltip('Remove Classes'));
    await tester.pumpAndSettle();
  });

  testWidgets('exam cards reuse the existing green accent in both themes', (
    tester,
  ) async {
    for (final brightness in Brightness.values) {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: const Scaffold(
            body: ExamCard(
              courseCode: 'EXAMPLE',
              sectionName: '01',
              isHighlighted: true,
            ),
          ),
        ),
      );
      expect(
        tester.widget<AppCard>(find.byType(AppCard)).highlightColor,
        AppPalette.accent,
      );
    }
  });

  testWidgets(
    'overlapping extra classes keep both class cards without warnings',
    (tester) async {
      final today = DateTime.now();
      final date = today.add(const Duration(days: 2));
      const weekdays = [
        'MONDAY',
        'TUESDAY',
        'WEDNESDAY',
        'THURSDAY',
        'FRIDAY',
        'SATURDAY',
        'SUNDAY',
      ];
      Section scheduled(int id) => Section.fromJson({
        ...sampleSection(id).toJson(),
        'sectionSchedule': {
          'classStartDate': today
              .subtract(const Duration(days: 1))
              .toIso8601String(),
          'classEndDate': today.add(const Duration(days: 30)).toIso8601String(),
          'classSchedules': [
            {
              'day': weekdays[date.weekday - 1],
              'startTime': '08:00',
              'endTime': '09:20',
            },
          ],
        },
      });
      SharedPreferences.setMockInitialValues({
        'currentSessionSemesterId': '1',
        'student_schedule_v1_1': jsonEncode([scheduled(1).toJson()]),
        'student_semester_sessions_v1': jsonEncode([
          {'semesterSessionId': 1, 'description': 'Example Semester'},
        ]),
        'student_semester_sessions_v1_fetched_at': today.millisecondsSinceEpoch
            .toString(),
        ExtraClassesStore.storageKey: jsonEncode([
          ExtraClass(
            section: scheduled(2),
            days: {weekdays[date.weekday - 1]},
          ).toJson(),
        ]),
      });
      await tester.runAsync(
        () => AppStorage.initialize(cacheDirectory: directory),
      );
      tester.view.physicalSize = const Size(500, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const MaterialApp(home: ClassSchedulePage()));
      await tester.pumpAndSettle();
      final cards = tester
          .widgetList<ScheduleEntryCard>(find.byType(ScheduleEntryCard))
          .toList();
      expect(
        cards.map((card) => card.courseCode),
        containsAll(['EXAMPLE1', 'EXAMPLE2']),
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
