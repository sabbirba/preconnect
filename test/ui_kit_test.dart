import 'package:flutter_test/flutter_test.dart';
import 'package:preconnect/pages/ui_kit.dart';

void main() {
  group('format helpers', () {
    test('formatDate parses and formats common date patterns', () {
      expect(formatDate('2026-02-11'), '11 February, 2026');
      expect(formatDate('11/02/2026'), '11 February, 2026');
    });

    test('formatSemesterFromSessionId converts numeric session ids', () {
      expect(formatSemesterFromSessionId('20261'), 'Spring 2026');
      expect(formatSemesterFromSessionId('20262'), 'Fall 2026');
      expect(formatSemesterFromSessionId('20263'), 'Summer 2026');
    });

    test('formatSectionBadge normalizes section numbers', () {
      expect(formatSectionBadge('Section 1'), '01');
      expect(formatSectionBadge('SEC-12'), '12');
      expect(formatSectionBadge('N/A'), '--');
    });
  });
}
