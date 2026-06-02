import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:preconnect/tools/token_storage.dart';
import 'package:preconnect/tools/preconnect_constants.dart';
import 'package:preconnect/tools/app_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TokenStorage Encryption & Fallback Tests', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('saves and reads plain text when key is not sensitive', () async {
      final storage = TokenStorage.instance;
      const key = 'non_sensitive_key';
      const value = 'hello_world';

      await storage.write(key: key, value: value);
      final readVal = await storage.read(key: key);

      expect(readVal, value);
    });

    test('falls back transparently to plain text for legacy stored tokens', () async {
      final storage = TokenStorage.instance;
      const key = PreconnectStorageKeys.accessToken;
      const legacyPlainToken = 'legacy_plain_text_token_value_123';

      await AppStorage.instance.setString(key, legacyPlainToken);

      final readVal = await storage.read(key: key);
      expect(readVal, legacyPlainToken);
    });

    test('saves sensitive keys securely and returns correct values', () async {
      final storage = TokenStorage.instance;
      const key = PreconnectStorageKeys.accessToken;
      const token = 'my_secure_session_token_123';

      await storage.write(key: key, value: token);
      final readVal = await storage.read(key: key);

      expect(readVal, token);
    });
  });
}
