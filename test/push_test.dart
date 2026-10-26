import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:preconnect/features/notifications/data/push_registration.dart';

void main() {
  test(
    'registration listens before requesting and coalesces concurrent callers',
    () async {
      final events = StreamController<String>.broadcast(sync: true);
      var calls = 0;
      final registration = PushRegistration(
        events: events.stream,
        register: () async {
          calls++;
          events.add('example_fid');
        },
      );
      expect(await Future.wait([registration.get(), registration.get()]), [
        'example_fid',
        'example_fid',
      ]);
      expect(calls, 1);
      expect(events.hasListener, isFalse);
      await events.close();
    },
  );

  test(
    'registration failures cancel listeners and allow a later retry',
    () async {
      final events = StreamController<String>.broadcast(sync: true);
      var fail = true;
      final registration = PushRegistration(
        events: events.stream,
        register: () async {
          if (fail) throw StateError('unavailable');
          events.add('new_example_fid');
        },
      );
      await expectLater(registration.get(), throwsStateError);
      expect(events.hasListener, isFalse);
      fail = false;
      expect(await registration.get(), 'new_example_fid');
      await events.close();
    },
  );

  test(
    'registration timeouts and stream errors release the subscription',
    () async {
      final events = StreamController<String>.broadcast(sync: true);
      final registration = PushRegistration(
        events: events.stream,
        register: () async {},
        timeout: const Duration(milliseconds: 10),
      );
      await expectLater(registration.get(), throwsA(isA<TimeoutException>()));
      expect(events.hasListener, isFalse);
      final pending = registration.get();
      events.addError(StateError('registration failed'));
      await expectLater(pending, throwsStateError);
      await events.close();
    },
  );
}
