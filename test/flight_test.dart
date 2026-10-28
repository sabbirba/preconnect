import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:preconnect/tools/in_flight.dart';

void main() {
  group('in flight work', () {
    test('a task completes with its value', () async {
      final flight = InFlight<String, int>();
      expect(await flight.run('a', () async => 7), 7);
      expect(flight.length, 0);
    });

    test('callers with the same key share one run', () async {
      final flight = InFlight<String, int>();
      final gate = Completer<int>();
      var runs = 0;
      final first = flight.run('a', () {
        runs++;
        return gate.future;
      });
      final second = flight.run('a', () {
        runs++;
        return gate.future;
      });
      expect(identical(first, second), isTrue);
      gate.complete(3);
      expect(await Future.wait([first, second]), [3, 3]);
      expect(runs, 1);
    });

    test('different keys run separately', () async {
      final flight = InFlight<String, int>();
      var runs = 0;
      await Future.wait([
        flight.run('a', () async => ++runs),
        flight.run('b', () async => ++runs),
      ]);
      expect(runs, 2);
    });

    test('a failure reaches every caller and the key can run again', () async {
      final flight = InFlight<String, int>();
      final gate = Completer<int>();
      final first = flight.run('a', () => gate.future);
      final second = flight.run('a', () => gate.future);
      final results = Future.wait([
        first.then<Object?>((value) => value, onError: (Object e) => 'failed'),
        second.then<Object?>((value) => value, onError: (Object e) => 'failed'),
      ]);
      gate.completeError(StateError('boom'));
      expect(await results, ['failed', 'failed']);
      await Future<void>.delayed(Duration.zero);
      expect(flight.length, 0);
      expect(await flight.run('a', () async => 9), 9);
    });

    test('never waits on itself', () async {
      final flight = InFlight<String, int>();
      final value = await flight
          .run('a', () async => 1)
          .timeout(const Duration(seconds: 1));
      expect(value, 1);
    });
  });
}
