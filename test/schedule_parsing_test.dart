import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:preconnect/api/seat_status.dart';
import 'package:preconnect/model/section_info.dart';

void main() {
  group('Section parsing', () {
    test('parses nested sectionSchedule when encoded as a string', () {
      final payload = jsonEncode([
        {
          'sectionId': 1,
          'advisingSectionId': null,
          'parentSectionId': null,
          'courseId': 101,
          'courseCode': 'CSE101',
          'name': 'Intro to Computing',
          'sectionName': 'A',
          'semesterSessionId': 20241,
          'courseCredit': 3,
          'studentPortfolioId': 9,
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
          'prerequisiteCourses': null,
          'isReserve': false,
          'courseType': 'Theory',
          'prerequisiteIncompleteGrade': null,
          'prerequisiteResultPublished': null,
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

    test('parses nested sectionSchedule when already decoded as a map', () {
      final payload = jsonEncode([
        {
          'sectionId': 2,
          'advisingSectionId': null,
          'parentSectionId': null,
          'courseId': 102,
          'courseCode': 'CSE102',
          'name': 'Data Structures',
          'sectionName': 'B',
          'semesterSessionId': 20241,
          'courseCredit': 3,
          'studentPortfolioId': 9,
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
          'prerequisiteCourses': null,
          'isReserve': false,
          'courseType': 'Lab',
          'prerequisiteIncompleteGrade': null,
          'prerequisiteResultPublished': null,
        },
      ]);

      final sections = parseSectionsFromScheduleJson(payload);

      expect(sections, hasLength(1));
      expect(sections.single.faculties, 'AB');
      expect(sections.single.sectionSchedule.classSchedules, hasLength(1));
      expect(
        sections.single.sectionSchedule.classSchedules.single.day,
        'Tuesday',
      );
    });
  });

  group('Seat status parsing', () {
    test('parses nested sectionSchedule when encoded as a string', () {
      final response = SeatStatusDetailsResponse.fromJson({
        'sectionId': 11,
        'courseId': 201,
        'courseCode': 'CSE201',
        'sectionName': 'A',
        'courseCredit': 3,
        'capacity': 40,
        'consumedSeat': 33,
        'semesterSessionId': 20241,
        'parentSectionId': null,
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
        'prerequisiteCourses': null,
        'sectionSchedule': jsonEncode({
          'classSchedules': [
            {'day': 'Thursday', 'startTime': '14:00', 'endTime': '15:30'},
          ],
          'midExamDate': '2026-02-15',
        }),
        'labSectionId': null,
        'labCourseCode': null,
        'labFaculties': null,
        'labName': null,
        'labRoomName': null,
        'labSchedules': [],
      });

      expect(response.faculties, 'CD');
      expect(response.sectionSchedule.classSchedules, hasLength(1));
      expect(response.sectionSchedule.classSchedules.single.day, 'Thursday');
    });
  });
}
