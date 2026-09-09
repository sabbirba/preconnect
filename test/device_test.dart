import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:preconnect/features/notifications/data/device_registry.dart';
import 'package:preconnect/tools/preconnect_constants.dart';

void main() {
  test(
    'registers and unregisters a push device with stable payloads',
    () async {
      final requests = <({String method, String url, String body})>[];
      final registry = PushDeviceRegistry(
        registerUrl: 'https://example.test/register',
        unregisterUrl: 'https://example.test/unregister',
        send:
            (
              method,
              url, {
              body = '',
              additionalHeaders = const <String, String>{},
            }) async {
              expect(additionalHeaders['Content-Type'], 'application/json');
              requests.add((method: method, url: url, body: body));
            },
      );

      await registry.register(token: 'device-token', platform: 'android');
      await registry.unregister('device-token');

      expect(requests[0].method, 'POST');
      expect(requests[0].url, 'https://example.test/register');
      expect(jsonDecode(requests[0].body), {
        'token': 'device-token',
        'platform': 'android',
      });
      expect(requests[1].method, 'POST');
      expect(requests[1].url, 'https://example.test/unregister');
      expect(jsonDecode(requests[1].body), {'token': 'device-token'});
    },
  );

  test('PreConnectPushConfig defaultTopics contains exact required topics', () {
    expect(PreConnectPushConfig.defaultTopics, <String>[
      'all',
      'announcements',
      'news',
      'wifi',
      'notice',
      'printer',
      'general',
      'exam',
      'holiday',
      'materials',
      'prerequisites',
    ]);
  });
}
