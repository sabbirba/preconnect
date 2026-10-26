import 'package:flutter_test/flutter_test.dart';
import 'package:preconnect/api/seat_status.dart';
import 'package:preconnect/model/section_info.dart';

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
}
