import 'package:flutter_test/flutter_test.dart';
import 'package:preconnect/api/seat_status.dart';
import 'package:preconnect/model/section_info.dart';
import 'package:preconnect/pages/shared_widgets/seat_card.dart';

void main() {
  test('faculty keeps gender and designation from the feed', () {
    final faculty = SectionFaculty.tryParse({
      'id': '1',
      'shortName': 'DEMO',
      'staffName': 'Example Faculty',
      'email': 'demo@example.com',
      'gender': 'Female',
      'designation': 'Lecturer',
    })!;
    expect(faculty.gender, 'Female');
    expect(faculty.designation, 'Lecturer');
    expect(seatStatusFacultyMeta(faculty), 'Female • Lecturer');

    final roundTrip = SeatStatusDetailsResponse.fromJson(
      SeatStatusDetailsResponse.fromJson({
        'faculties': faculty.toJson(),
      }).toJson(),
    ).faculty;
    expect(roundTrip?.designation, 'Lecturer');
  });

  test('faculty meta is empty when the feed has no details', () {
    expect(seatStatusFacultyMeta(SectionFaculty.tryParse('DEMO')), '');
    expect(seatStatusFacultyMeta(null), '');
  });
}
