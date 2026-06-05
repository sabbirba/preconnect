import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:preconnect/api/fcm.dart';
import 'package:preconnect/tools/app_storage.dart';
import 'package:preconnect/tools/storage_keys.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FCMService Email Resolution and Support Tests', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await AppStorage.initialize();
    });

    test('resolveEmail returns null when email is not in storage', () async {
      final email = await FCMService.instance.resolveEmail();
      expect(email, isNull);
    });

    test('resolveEmail returns trimmed lowercase email when present in storage', () async {
      await AppStorage.instance.setString(
        StorageKeys.studentEmail,
        '  John.Doe@Bracu.Ac.Bd  ',
      );

      final email = await FCMService.instance.resolveEmail();
      expect(email, 'john.doe@bracu.ac.bd');
    });

    test('isSupported returns true for Android target platform', () {
      final supported = FCMService.instance.isSupported;
      expect(supported, isTrue);
    });
  });
}
