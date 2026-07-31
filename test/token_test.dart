import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:preconnect/features/auth/data/oauth_exchange.dart';
import 'package:preconnect/tools/app_storage.dart';
import 'package:preconnect/tools/preconnect_constants.dart';
import 'package:preconnect/tools/token_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('migrates every sensitive value out of plaintext storage', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    SharedPreferences.setMockInitialValues(<String, Object>{
      PreConnectStorageKeys.accessToken: 'legacy-access',
      PreConnectStorageKeys.refreshToken: 'legacy-refresh',
      PreConnectStorageKeys.idToken: 'legacy-id',
      'wifi_captive_password': 'legacy-wifi',
    });
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    await AppStorage.initialize();

    expect(
      await TokenStorage.instance.read(key: PreConnectStorageKeys.accessToken),
      'legacy-access',
    );

    const secureStorage = FlutterSecureStorage(
      mOptions: MacOsOptions(usesDataProtectionKeychain: true),
    );
    final preferences = await SharedPreferences.getInstance();
    for (final key in const <String>[
      PreConnectStorageKeys.accessToken,
      PreConnectStorageKeys.refreshToken,
      PreConnectStorageKeys.idToken,
      'wifi_captive_password',
    ]) {
      expect(await secureStorage.read(key: key), isNotNull);
      expect(preferences.containsKey(key), isFalse);
    }

    await OAuthCodeExchange().persist(
      const AuthTokens(
        accessToken: 'replacement-access',
        refreshToken: 'replacement-refresh',
      ),
    );
    expect(
      await secureStorage.read(key: PreConnectStorageKeys.idToken),
      isNull,
    );

    await TokenStorage.instance.deleteAll();
    for (final key in const <String>[
      PreConnectStorageKeys.accessToken,
      PreConnectStorageKeys.refreshToken,
      PreConnectStorageKeys.idToken,
      'wifi_captive_password',
    ]) {
      expect(await secureStorage.read(key: key), isNull);
    }
  });
}
