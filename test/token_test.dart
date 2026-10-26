import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:preconnect/api/auth.dart';
import 'package:preconnect/libsync/libsync_client.dart';
import 'package:preconnect/tools/app_storage.dart';
import 'package:preconnect/tools/token_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final secureValues = <String, String>{};
  String? failedMethod;
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('preconnect_tokens_');
    SharedPreferences.setMockInitialValues({});
    await AppStorage.initialize(cacheDirectory: directory);
    secureValues.clear();
    failedMethod = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == failedMethod) {
            throw PlatformException(code: 'storage_unavailable');
          }
          final args = Map<String, dynamic>.from(call.arguments as Map);
          final key = args['key'] as String;
          switch (call.method) {
            case 'read':
              return secureValues[key];
            case 'write':
              secureValues[key] = args['value'] as String;
            case 'delete':
              secureValues.remove(key);
          }
          return null;
        });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await directory.delete(recursive: true);
  });

  test('failed migration preserves legacy values and can retry', () async {
    await AppStorage.instance.setString('access_token', 'synthetic_access');
    final storage = TokenStorage();
    failedMethod = 'write';
    await expectLater(
      storage.read(key: 'access_token'),
      throwsA(isA<TokenPersistenceException>()),
    );
    expect(
      await AppStorage.instance.getString('access_token'),
      'synthetic_access',
    );
    failedMethod = null;
    expect(await storage.read(key: 'access_token'), 'synthetic_access');
    expect(await AppStorage.instance.getString('access_token'), isNull);
    expect(secureValues['access_token'], 'synthetic_access');
  });

  test('failed secure writes cannot mark a session as saved', () async {
    failedMethod = 'write';
    await expectLater(
      TokenStorage().write(key: 'access_token', value: 'synthetic_access'),
      throwsA(isA<TokenPersistenceException>()),
    );
    expect(
      await AppStorage.instance.getBool('cached_has_auth_session'),
      isNull,
    );
  });

  test('secure read and delete failures are surfaced', () async {
    final storage = TokenStorage();
    await storage.write(key: 'access_token', value: 'synthetic_access');
    failedMethod = 'read';
    await expectLater(
      storage.read(key: 'access_token'),
      throwsA(isA<TokenPersistenceException>()),
    );
    failedMethod = 'delete';
    await expectLater(
      storage.deleteAll(),
      throwsA(isA<TokenPersistenceException>()),
    );
    expect(secureValues['access_token'], 'synthetic_access');
  });

  test(
    'LibSync credentials stay out of preferences and retries use new tokens',
    () async {
      var gets = 0;
      final client = LibSyncApiClient(
        client: MockClient((request) async {
          if (request.method == 'POST') {
            return http.Response(
              jsonEncode({
                'access': 'synthetic_new',
                'refresh': 'synthetic_refresh',
              }),
              200,
            );
          }
          gets++;
          if (gets == 1) return http.Response('expired', 401);
          expect(request.headers['Authorization'], 'Bearer synthetic_new');
          return http.Response(
            '{}',
            200,
            headers: {'set-cookie': 'csrftoken=synthetic_cookie; Secure'},
          );
        }),
      );
      await client.saveCookies({
        'access': 'synthetic_old',
        'refresh': 'synthetic_refresh',
      });
      expect(await AppStorage.instance.getString('libsync_cookies'), isNull);
      expect(
        await client
            .get(Uri.parse('https://libsync.bracu.ac.bd/api/test/'))
            .then((response) => response.statusCode),
        200,
      );
      expect(gets, 2);
      expect(
        await AppStorage.instance.getString('libsync_headers_cache'),
        isNot(contains('synthetic_cookie')),
      );
      await client.clearAuthData();
      expect(secureValues['libsync_cookies'], isNull);
      client.close();
    },
  );

  test('JWT expiry parsing rejects malformed values and preserves expiry', () {
    String encode(Object value) =>
        base64Url.encode(utf8.encode(jsonEncode(value)));
    final valid =
        '${encode({'alg': 'synthetic'})}.${encode({'exp': 1900000000})}.${encode('signature')}';
    expect(
      AuthService.tokenExpiry(valid).millisecondsSinceEpoch,
      1900000000000,
    );
    for (final token in [null, '', 'invalid', 'a.b.c', '...']) {
      expect(AuthService.tokenExpiry(token).millisecondsSinceEpoch, 0);
    }
  });
}
