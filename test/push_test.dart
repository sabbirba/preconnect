import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:preconnect/features/notifications/data/device_registry.dart';
import 'package:preconnect/features/notifications/data/push_registration.dart';

void main() {
  test('push registration validates the server acknowledgement', () async {
    var status = 500;
    var payload = '{"ok":true}';
    final requests = <http.Request>[];
    final registry = PushDeviceRegistry(
      registerUrl: 'https://example.test/register',
      unregisterUrl: 'https://example.test/unregister',
      client: MockClient((request) async {
        requests.add(request);
        return http.Response(payload, status);
      }),
    );
    await expectLater(
      registry.register(token: 'synthetic_registration', platform: 'android'),
      throwsStateError,
    );
    status = 200;
    payload = '{"ok":false}';
    await expectLater(
      registry.post('https://example.test/subscribe', {'topic': 'all'}),
      throwsStateError,
    );
    payload = '{"ok":true}';
    await registry.register(
      token: 'synthetic_registration',
      platform: 'android',
    );
    expect(jsonDecode(requests.last.body), {
      'token': 'synthetic_registration',
      'platform': 'android',
    });
    await registry.unregister('synthetic_registration');
    expect(requests.last.url.path, '/unregister');
  });

  test('push registration bounds stalled requests', () async {
    final registry = PushDeviceRegistry(
      registerUrl: 'https://example.test/register',
      unregisterUrl: 'https://example.test/unregister',
      timeout: const Duration(milliseconds: 10),
      client: MockClient((_) => Completer<http.Response>().future),
    );
    await expectLater(
      registry.register(token: 'synthetic_registration', platform: 'web'),
      throwsA(isA<TimeoutException>()),
    );
  });

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
      expect(events.hasListener, isFalse);
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
      expect(events.hasListener, isFalse);
      await events.close();
    },
  );
}
