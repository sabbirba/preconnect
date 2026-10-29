import 'package:flutter_test/flutter_test.dart';
import 'package:preconnect/api/seat_stream.dart';

void main() {
  test('parses a section update into one seat count', () {
    final counts = parseSeatEvent(
      'section-updated',
      '{"type":"event.section-updated","data":{"section":42,"delta":2,"total":31,"capacity":40}}',
    );
    expect(counts, hasLength(1));
    expect(counts.single.sectionId, 42);
    expect(counts.single.consumed, 31);
    expect(counts.single.capacity, 40);
  });

  test('parses a snapshot map into counts without capacity', () {
    final counts = parseSeatEvent('seat-snapshot', '{"101":0,"185762":29}');
    expect(counts.map((count) => count.sectionId), [101, 185762]);
    expect(counts.map((count) => count.consumed), [0, 29]);
    expect(counts.every((count) => count.capacity == null), isTrue);
  });

  test('ignores unknown events and malformed payloads', () {
    expect(parseSeatEvent('ping', '{}'), isEmpty);
    expect(parseSeatEvent('section-updated', 'not json'), isEmpty);
    expect(
      parseSeatEvent('section-updated', '{"data":{"section":1}}'),
      isEmpty,
    );
  });
}
