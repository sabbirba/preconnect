import 'package:flutter_test/flutter_test.dart';
import 'package:preconnect/api/seat_status.dart';
import 'package:preconnect/tools/course_prereq.dart';
import 'package:preconnect/tools/routine_clash.dart';

SeatStatusDetailsResponse section(
  int id,
  String course,
  String name,
  List<List<String>> classes, {
  List<List<String>> labs = const <List<String>>[],
  int capacity = 30,
  int consumed = 10,
}) {
  Map<String, String> slot(List<String> value) => <String, String>{
    'day': value[0],
    'startTime': value[1],
    'endTime': value[2],
  };
  return SeatStatusDetailsResponse.fromJson(<String, dynamic>{
    'sectionId': id,
    'courseCode': course,
    'sectionName': name,
    'courseCredit': 3,
    'capacity': capacity,
    'consumedSeat': consumed,
    'sectionSchedule': <String, dynamic>{
      'classSchedules': [for (final value in classes) slot(value)],
    },
    'labSchedules': [for (final value in labs) slot(value)],
  });
}

void main() {
  group('routine clash', () {
    test('same day overlapping class times clash', () {
      final a = section(1, 'CSE110', '01', [
        ['SUNDAY', '08:00:00', '09:20:00'],
      ]);
      final b = section(2, 'MAT110', '01', [
        ['SUNDAY', '09:00:00', '10:20:00'],
      ]);
      expect(blocksClash(sectionBlocks(a), sectionBlocks(b)), isTrue);
    });

    test('back to back and different day classes do not clash', () {
      final a = section(1, 'CSE110', '01', [
        ['SUNDAY', '08:00:00', '09:20:00'],
      ]);
      final b = section(2, 'MAT110', '01', [
        ['SUNDAY', '09:20:00', '10:40:00'],
      ]);
      final c = section(3, 'PHY111', '01', [
        ['MONDAY', '08:00:00', '09:20:00'],
      ]);
      expect(blocksClash(sectionBlocks(a), sectionBlocks(b)), isFalse);
      expect(blocksClash(sectionBlocks(a), sectionBlocks(c)), isFalse);
    });

    test('lab time clashes with another class', () {
      final a = section(
        1,
        'CSE110',
        '01',
        [
          ['SUNDAY', '08:00:00', '09:20:00'],
        ],
        labs: [
          ['TUESDAY', '14:00:00', '16:50:00'],
        ],
      );
      final b = section(2, 'MAT110', '01', [
        ['TUESDAY', '15:30:00', '16:50:00'],
      ]);
      expect(blocksClash(sectionBlocks(a), sectionBlocks(b)), isTrue);
    });
  });

  group('best section', () {
    test('skips full and clashing sections', () {
      final picked = [
        section(1, 'CSE110', '01', [
          ['SUNDAY', '08:00:00', '09:20:00'],
        ]),
      ];
      final best = bestSectionFor([
        section(2, 'MAT110', '01', [
          ['MONDAY', '08:00:00', '09:20:00'],
        ], consumed: 30),
        section(3, 'MAT110', '02', [
          ['SUNDAY', '08:30:00', '09:50:00'],
        ]),
        section(4, 'MAT110', '03', [
          ['TUESDAY', '11:00:00', '12:20:00'],
        ]),
      ], picked);
      expect(best?.sectionId, 4);
    });

    test('prefers days already in the routine, then more seats', () {
      final picked = [
        section(1, 'CSE110', '01', [
          ['SUNDAY', '08:00:00', '09:20:00'],
        ]),
      ];
      final best = bestSectionFor([
        section(2, 'MAT110', '01', [
          ['MONDAY', '11:00:00', '12:20:00'],
        ], consumed: 0),
        section(3, 'MAT110', '02', [
          ['SUNDAY', '11:00:00', '12:20:00'],
        ], consumed: 25),
        section(4, 'MAT110', '03', [
          ['SUNDAY', '14:00:00', '15:20:00'],
        ], consumed: 20),
      ], picked);
      expect(best?.sectionId, 4);
    });

    test('returns nothing when every option clashes or is full', () {
      expect(bestSectionFor(const [], const []), isNull);
    });
  });

  group('prerequisites', () {
    test('and binds tighter than or', () {
      expect(
        prerequisiteSatisfied('CSE110 OR CSE111 AND MAT110', {'CSE110'}),
        isTrue,
      );
      expect(prerequisiteSatisfied('CSE110 AND MAT110', {'CSE110'}), isFalse);
    });

    test('a satisfied left side of or does not skip the rest', () {
      expect(
        prerequisiteSatisfied('(CSE110 OR CSE111) AND MAT110', {'CSE110'}),
        isFalse,
      );
      expect(
        prerequisiteSatisfied('(CSE110 OR CSE111) AND MAT110', {
          'CSE110',
          'MAT110',
        }),
        isTrue,
      );
    });

    test('empty and placeholder prerequisites are satisfied', () {
      expect(prerequisiteSatisfied('', const {}), isTrue);
      expect(prerequisiteSatisfied('N/A', const {}), isTrue);
    });
  });
}
