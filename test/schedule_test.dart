import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:preconnect/api/seat_status.dart';
import 'package:preconnect/model/section_info.dart';

void main() {
  group('section parsing', () {
    test('parses a string-encoded section schedule', () {
      final payload = jsonEncode([
        {
          'sectionId': 1,
          'courseId': 101,
          'courseCode': 'CSE101',
          'name': 'Intro to Computing',
          'sectionName': 'A',
          'semesterSessionId': 20241,
          'courseCredit': 3,
          'capacity': 30,
          'consumedSeat': 20,
          'sectionSchedule': jsonEncode({
            'classStartDate': '2026-01-01',
            'classEndDate': '2026-04-01',
            'classSchedules': [
              {'day': 'Monday', 'startTime': '09:00', 'endTime': '10:30'},
              {'day': 'Wednesday', 'startTime': '09:00', 'endTime': '10:30'},
            ],
          }),
          'faculties': 'Dr. Example',
          'roomName': 'Main Building',
          'roomNumber': '101',
          'isReserve': false,
          'courseType': 'Theory',
        },
      ]);

      final sections = parseSectionsFromScheduleJson(payload);

      expect(sections, hasLength(1));
      expect(sections.single.sectionSchedule.classSchedules, hasLength(2));
      expect(
        sections.single.sectionSchedule.classSchedules.first.day,
        'Monday',
      );
    });

    test('parses an already-decoded section schedule', () {
      final payload = jsonEncode([
        {
          'sectionId': 2,
          'courseId': 102,
          'courseCode': 'CSE102',
          'name': 'Data Structures',
          'sectionName': 'B',
          'semesterSessionId': 20241,
          'courseCredit': 3,
          'capacity': 30,
          'consumedSeat': 20,
          'sectionSchedule': {
            'classStartDate': '2026-01-01',
            'classEndDate': '2026-04-01',
            'classSchedules': [
              {'day': 'Tuesday', 'startTime': '11:00', 'endTime': '12:30'},
            ],
          },
          'faculties': {
            'shortName': 'AB',
            'staffName': 'Alice Brown',
            'email': 'alice@example.com',
          },
          'roomName': 'Lab',
          'roomNumber': '202',
          'isReserve': false,
          'courseType': 'Lab',
        },
      ]);

      final sections = parseSectionsFromScheduleJson(payload);

      expect(sections, hasLength(1));
      expect(sections.single.faculties, 'AB');
      expect(
        sections.single.sectionSchedule.classSchedules.single.day,
        'Tuesday',
      );
    });
  });

  test('parses a seat-status schedule encoded as a string', () {
    final response = SeatStatusDetailsResponse.fromJson({
      'sectionId': 11,
      'courseId': 201,
      'courseCode': 'CSE201',
      'sectionName': 'A',
      'courseCredit': 3,
      'capacity': 40,
      'consumedSeat': 33,
      'semesterSessionId': 20241,
      'faculties': {
        'shortName': 'CD',
        'staffName': 'Carol Danvers',
        'email': 'carol@example.com',
      },
      'roomName': 'Room 303',
      'roomNumber': '303',
      'courseType': 'Theory',
      'academicDegree': 'CSE',
      'sectionType': 'Regular',
      'courseName': 'Algorithms',
      'sectionSchedule': jsonEncode({
        'classSchedules': [
          {'day': 'Thursday', 'startTime': '14:00', 'endTime': '15:30'},
        ],
        'midExamDate': '2026-02-15',
      }),
      'labSchedules': [],
    });

    expect(response.faculties, 'CD');
    expect(response.sectionSchedule.classSchedules.single.day, 'Thursday');
  });
}
