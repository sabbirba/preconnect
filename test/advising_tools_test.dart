import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/model/advising_phase.dart';
import 'package:preconnect/model/section_info.dart';
import 'package:preconnect/pages/advising_helper.dart';
import 'package:preconnect/pages/advising_phase.dart';
import 'package:preconnect/pages/lab_sections.dart';
import 'package:preconnect/pages/wishlist.dart';

void main() {
  test('Wishlist uses the captured API contracts and exact list shape', () {
    expect(
      ApiConfig.wishlistSessionPath('70801', 'request-key'),
      '/adv/v1/advising/70801/wishlist-session?publicKey=request-key',
    );
    expect(ApiConfig.wishlistCoursesPath('70801'), '/adv/v1/wishlists/70801');
    expect(
      ApiConfig.wishlistOfferedCoursesPath('70801'),
      '/adv/v1/wishlists/70801/offered-courses',
    );
    expect(ApiConfig.wishlistMutationPath, '/adv/v1/wishlists');

    final course = <String, dynamic>{
      'courseCode': 'CSE220',
      'courseCredit': 3,
      'courseId': 2052,
      'name': 'DATA STRUCTURES',
    };
    expect(parseWishlistCourseList(jsonEncode(<Object>[course])), <Object>[
      course,
    ]);
    expect(
      () => parseWishlistCourseList(
        jsonEncode(<String, dynamic>{
          'courses': <Object>[course],
        }),
      ),
      throwsFormatException,
    );
  });

  test('Wishlist preselection matches courses only by course ID', () {
    final selected = <Map<String, dynamic>>[
      <String, dynamic>{
        'courseId': 2052,
        'courseCode': 'CSE220',
        'name': 'DATA STRUCTURES',
        'courseCredit': 3,
      },
    ];

    expect(
      wishlistContainsCourse(selected, <String, dynamic>{
        'courseId': 2052,
        'courseCode': 'CSE220',
        'name': 'DATA STRUCTURES',
        'courseCredit': 3,
        'sectionId': 99,
      }),
      isTrue,
    );
    expect(
      wishlistContainsCourse(selected, <String, dynamic>{
        'courseId': 2053,
        'courseCode': 'CSE220',
        'name': 'DATA STRUCTURES',
        'courseCredit': 3,
      }),
      isFalse,
    );
  });

  test('Wishlist course options include selected courses omitted by API', () {
    final selectedCourse = <String, dynamic>{
      'courseId': 2052,
      'courseCode': 'CSE220',
      'name': 'DATA STRUCTURES',
      'courseCredit': 3,
    };
    final offeredCourse = <String, dynamic>{
      'courseId': 2053,
      'courseCode': 'CSE221',
      'name': 'ALGORITHMS',
      'courseCredit': 3,
    };

    final options = mergeWishlistCourseOptions(
      <Map<String, dynamic>>[selectedCourse],
      <Map<String, dynamic>>[selectedCourse, offeredCourse],
    );

    expect(options, <Map<String, dynamic>>[selectedCourse, offeredCourse]);
    expect(options.map(wishlistCourseId).toSet(), <int>{2052, 2053});
  });

  for (final phase in AdvisingPhase.values) {
    testWidgets('${phase.label} delegates to the shared advising helper', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(home: AdvisingPhasePage(phase: phase)),
      );

      final helper = tester.widget<AdvisingHelperPage>(
        find.byType(AdvisingHelperPage),
      );
      expect(helper.initialPhase, phase);
    });
  }

  testWidgets('lab sections load tabs lazily', (tester) async {
    final calls = <String>[];
    Future<List<Section>> load(
      String phase, {
      bool forceRefresh = false,
    }) async {
      calls.add(phase);
      return const <Section>[];
    }

    await tester.pumpWidget(
      MaterialApp(home: LabSectionsPage(loadSections: load)),
    );
    await tester.pumpAndSettle();

    expect(calls, <String>['PHASE_ONE']);

    await tester.tap(find.text('Phase 2'));
    await tester.pumpAndSettle();

    expect(calls, <String>['PHASE_ONE', 'PHASE_TWO']);
  });
}
