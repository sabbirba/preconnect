import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:preconnect/api/wishlist_engine.dart';
import 'package:preconnect/tools/string_utils.dart';

Map<String, dynamic> _course(int id, String code, int credit) => {
  'courseId': id,
  'courseCode': code,
  'name': 'Sample Course $code',
  'courseCredit': credit,
};

void main() {
  test('reads the credit limit from the wishlist session', () {
    final body = jsonEncode({'minLoad': 9, 'maxLoad': 13, 'id': 1});
    expect(parseWishlistCreditLimit(body), (min: 9, max: 13));
    expect(parseWishlistCreditLimit(jsonEncode({'minLoad': 9})), isNull);
    expect(parseWishlistCreditLimit('[]'), isNull);
  });

  test('reads the confirmed status', () {
    expect(parseWishlistConfirmed('{"status": true}'), isTrue);
    expect(parseWishlistConfirmed('{"status": false}'), isFalse);
    expect(parseWishlistConfirmed('{}'), isFalse);
  });

  test('sums credits and checks them against the limit', () {
    final courses = [_course(1, 'AAA101', 3), _course(2, 'BBB201', 4)];
    expect(wishlistCredits(courses), 7);
    expect(isWithinWishlistLimit(7, (min: 9, max: 13)), isFalse);
    expect(isWithinWishlistLimit(9, (min: 9, max: 13)), isTrue);
    expect(isWithinWishlistLimit(14, (min: 9, max: 13)), isFalse);
    expect(isWithinWishlistLimit(0, null), isTrue);
  });

  test('lists selected courses first without duplicates', () {
    final selected = [_course(2, 'BBB201', 3)];
    final offered = [
      _course(1, 'AAA101', 3),
      _course(2, 'BBB201', 3),
      _course(3, 'CCC301', 4),
    ];
    final merged = mergeWishlistCourseOptions(selected, offered);
    expect(merged.map(wishlistCourseId), [2, 1, 3]);
    expect(wishlistContainsCourse(selected, offered[1]), isTrue);
    expect(wishlistContainsCourse(selected, offered[0]), isFalse);
  });

  test('rejects incomplete course records', () {
    final body = jsonEncode([
      {'courseId': 1, 'courseCode': 'AAA101', 'name': '', 'courseCredit': 3},
    ]);
    expect(() => parseWishlistCourseList(body), throwsFormatException);
  });

  test('normalizes wishlist course codes', () {
    expect(wishlistCourseCode({'courseCode': ' abc 101 '}), 'ABC101');
    expect(wishlistCourseCode({'courseCode': 'Xyz202'}), 'XYZ202');
    expect(wishlistCourseCode(<String, dynamic>{}), '');
  });

  test('round trips a queued wishlist course through json', () {
    final item = WishlistQueueItem(
      code: 'abc101',
      name: 'Sample Course ABC101',
      credit: 3,
      status: WishlistQueueStatus.failed,
      note: 'Not offered',
    );
    final restored = WishlistQueueItem.fromJson(
      jsonDecode(jsonEncode(item.toJson())) as Map<String, dynamic>,
    );
    expect(restored.code, 'ABC101');
    expect(restored.name, 'Sample Course ABC101');
    expect(restored.credit, 3);
    expect(restored.status, WishlistQueueStatus.failed);
    expect(restored.note, 'Not offered');

    final fallback = WishlistQueueItem.fromJson({
      'code': 'xyz202',
      'status': 'unknown',
    });
    expect(fallback.status, WishlistQueueStatus.queued);
    expect(fallback.credit, 0);
    expect(fallback.note, isNull);
  });

  test('title cases course names and count labels', () {
    expect(
      titleCaseText('MATHEMATICS III: COMPLEX VARIABLES & LAPLACE'),
      'Mathematics III: Complex Variables & Laplace',
    );
    expect(
      titleCaseText('INTRODUCTION TO POLITICAL SCIENCE'),
      'Introduction to Political Science',
    );
    expect(countLabel(1, 'Credit'), '1 Credit');
    expect(countLabel(15, 'Credit'), '15 Credits');
  });
}
