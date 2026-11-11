import 'package:flutter_test/flutter_test.dart';
import 'package:preconnect/model/section_info.dart';
import 'package:preconnect/pages/custom_sections/schedules_shared.dart';

Section _section(String course, String name, List<List<String>> slots) {
  return Section.fromJson(<String, dynamic>{
    'courseCode': course,
    'sectionName': name,
    'sectionSchedule': <String, dynamic>{
      'classSchedules': [
        for (final slot in slots)
          <String, String>{
            'day': slot[0],
            'startTime': slot[1],
            'endTime': slot[2],
          },
      ],
    },
  });
}

const _weekdays = <String>[
  'MONDAY',
  'TUESDAY',
  'WEDNESDAY',
  'THURSDAY',
  'FRIDAY',
  'SATURDAY',
  'SUNDAY',
];

void main() {
  final sections = [
    _section('CSE230', '07', [
      ['SUNDAY', '11:00:00', '12:20:00'],
      ['TUESDAY', '11:00:00', '12:20:00'],
    ]),
    _section('CSE230', '02', [
      ['MONDAY', '08:00:00', '09:20:00'],
    ]),
    _section('MAT110', '01', [
      ['WEDNESDAY', '14:00:00', '15:20:00'],
    ]),
  ];

  test('the next class of the room section is the default time', () {
    final next = personalSchedulesNextClassStart(
      sections,
      courseCode: 'CSE230',
      sectionName: '07',
      isRamadan: false,
    );
    expect(next, isNotNull);
    expect(next!.isAfter(DateTime.now()), isTrue);
    expect(next.hour, 11);
    expect(next.minute, 0);
    expect(_weekdays[next.weekday - 1], anyOf('SUNDAY', 'TUESDAY'));
  });

  test('course codes match regardless of case and spacing', () {
    final next = personalSchedulesNextClassStart(
      sections,
      courseCode: ' mat110 ',
      sectionName: '01',
      isRamadan: false,
    );
    expect(next?.hour, 14);
    expect(next == null ? null : _weekdays[next.weekday - 1], 'WEDNESDAY');
  });

  test('a course the student is not enrolled in gives no time', () {
    expect(
      personalSchedulesNextClassStart(
        sections,
        courseCode: 'PHY111',
        sectionName: '01',
        isRamadan: false,
      ),
      isNull,
    );
  });

  group('next class occurrence', () {
    final wednesday = DateTime(2030, 1, 2, 12, 0);

    CustomSchedulesOccurrence? next(String day, String start) {
      return personalSchedulesNextOccurrenceRange(
        day: day,
        startTime: start,
        endTime: '23:00:00',
        isRamadan: false,
        now: wednesday,
        nowMinutes: wednesday.hour * 60 + wednesday.minute,
      );
    }

    test('a class later today is today', () {
      expect(
        next('WEDNESDAY', '14:00:00')?.startTime,
        DateTime(2030, 1, 2, 14),
      );
    });

    test('a class that already started today is next week', () {
      expect(next('WEDNESDAY', '08:00:00')?.startTime, DateTime(2030, 1, 9, 8));
    });

    test('a class on another day is that coming day', () {
      expect(
        next('MONDAY', '09:30:00')?.startTime,
        DateTime(2030, 1, 7, 9, 30),
      );
    });
  });
}
