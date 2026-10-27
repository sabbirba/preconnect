import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/tools/string_utils.dart';

void main() {
  group('formatAmount', () {
    test('groups digits the Bangladeshi way', () {
      expect(formatAmount(999), '999');
      expect(formatAmount(12345), '12,345');
      expect(formatAmount(123456), '1,23,456');
      expect(formatAmount(1234.6), '1,235');
      expect(formatAmount(-1234), '-1,234');
    });
  });

  group('course and section names', () {
    test('course codes are trimmed and upper case', () {
      expect(normalizeCourseCode(' cse111 '), 'CSE111');
    });

    test('numeric sections lose leading zeros, others are upper case', () {
      expect(normalizeSectionName('01'), '1');
      expect(normalizeSectionName(' 12 '), '12');
      expect(normalizeSectionName('a'), 'A');
      expect(normalizeSectionName(''), '');
    });
  });

  group('looksLikePdf', () {
    test('finds the header at the start or within the first kilobyte', () {
      expect(looksLikePdf(utf8.encode('%PDF-1.7\nrest')), isTrue);
      expect(
        looksLikePdf([...List.filled(500, 0x20), ...utf8.encode('%PDF')]),
        isTrue,
      );
    });

    test('rejects short or unrelated data', () {
      expect(looksLikePdf(utf8.encode('PDF')), isFalse);
      expect(looksLikePdf(utf8.encode('hello world')), isFalse);
      expect(
        looksLikePdf([...List.filled(2000, 0x20), ...utf8.encode('%PDF')]),
        isFalse,
      );
    });
  });

  group('rooms', () {
    const combined = 'SUN 2:00PM: 07A-08C; TUE 2:00PM: 09G-31T';

    test('roomForDay picks the room for one day', () {
      expect(roomForDay(combined, 'TUESDAY'), '09G-31T');
      expect(roomForDay(combined, 'SUNDAY'), '07A-08C');
      expect(roomForDay(combined, 'MONDAY'), '');
      expect(roomForDay('Room 5', 'MONDAY'), 'Room 5');
    });

    test('roomsForDays joins the distinct rooms of several days', () {
      expect(roomsForDays(combined, ['SUNDAY', 'TUESDAY']), '07A-08C, 09G-31T');
      expect(roomsForDays('Room 5', ['SUNDAY', 'TUESDAY']), 'Room 5');
    });
  });

  group('pkceAuthUrl', () {
    test('builds the query with encoded values', () {
      final url = ApiConfig.pkceAuthUrl(
        endpoint: 'https://sso.example/auth',
        clientId: 'client',
        redirectUri: 'https://app.example/cb?x=1',
        codeChallenge: 'a+b/c=',
      );
      final uri = Uri.parse(url);
      expect(uri.queryParameters['client_id'], 'client');
      expect(uri.queryParameters['redirect_uri'], 'https://app.example/cb?x=1');
      expect(uri.queryParameters['code_challenge'], 'a+b/c=');
      expect(uri.queryParameters['code_challenge_method'], 'S256');
      expect(uri.queryParameters['response_type'], 'code');
    });
  });
}
