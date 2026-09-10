import 'package:flutter_test/flutter_test.dart';
import 'package:preconnect/libsync/availability_response.dart';

void main() {
  test('preserves useful API messages from object and list responses', () {
    for (final body in [
      '{"message":"You can reserve slots 7 days in advance"}',
      '[{"message":"You can reserve slots 7 days in advance"}]',
      '{"detail":"You can reserve slots 7 days in advance"}',
    ]) {
      expect(
        () => parseAvailabilityResponse(400, body),
        throwsA(
          isA<AvailabilityException>().having(
            (error) => error.message,
            'message',
            'You can reserve slots 7 days in advance',
          ),
        ),
      );
    }
  });

  test('uses a default for malformed and technical error responses', () {
    for (final body in [
      '<html>Bad gateway</html>',
      '',
      '{"error":{"debug":"raw data"}}',
      '{"message":"Exception: internal failure"}',
      '{"message":null}',
      '[42]',
    ]) {
      expect(
        () => parseAvailabilityResponse(200, body),
        throwsA(
          isA<AvailabilityException>().having(
            (error) => error.message,
            'message',
            AvailabilityException.defaultMessage,
          ),
        ),
      );
    }
  });

  test('preserves available rooms and empty successful results', () {
    expect(parseAvailabilityResponse(200, '[]'), isEmpty);
    expect(
      parseAvailabilityResponse(
        200,
        '[{"room":{"room_no":"Demo"},"slots":[]}]',
      ),
      hasLength(1),
    );
    expect(
      () => parseAvailabilityResponse(503, '[]'),
      throwsA(isA<AvailabilityException>()),
    );
  });
}
