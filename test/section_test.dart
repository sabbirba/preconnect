import 'package:flutter_test/flutter_test.dart';
import 'package:preconnect/api/seat_status.dart';
import 'package:preconnect/model/section_info.dart';
import 'package:preconnect/pages/custom_sections/schedules_shared.dart';

void main() {
  test('schedule and seat details accept the same faculty formats', () {
    for (final value in [
      null,
      '',
      ' tba ',
      ' DEMO ',
      {'id': 'demo', 'name': 'Example Faculty', 'shortName': 'DEMO'},
    ]) {
      final payload = <String, dynamic>{'faculties': value};
      final schedule = Section.fromJson(payload).faculty;
      final seats = SeatStatusDetailsResponse.fromJson(payload).faculty;
      expect(schedule?.toJson(), seats?.toJson());
      if (value is Map) {
        expect(schedule?.staffName, 'Example Faculty');
      } else if (value == ' DEMO ') {
        expect(schedule?.shortName, 'DEMO');
      } else {
        expect(schedule, isNull);
      }
    }
  });

  test('course options keep one entry per section in code order', () {
    Section section(String code) => Section.fromJson({
      'sectionId': code.hashCode,
      'courseCode': code,
      'sectionName': '01',
      'sectionSchedule': {
        'classSchedules': [
          {'day': 'SUNDAY', 'startTime': '08:00:00', 'endTime': '09:20:00'},
          {'day': 'MONDAY', 'startTime': '09:30:00', 'endTime': '10:50:00'},
        ],
      },
    });
    final options = courseOptionsFromSections([
      section('EXAMPLE2'),
      section(' example1 '),
      section('EXAMPLE2'),
    ]);
    expect(options.map((option) => option.courseCode), [
      'EXAMPLE1',
      'EXAMPLE2',
    ]);
    expect(options.first.classSchedules.map((slot) => slot.day), [
      'SUNDAY',
      'MONDAY',
    ]);
  });
}
