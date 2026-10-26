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


}
