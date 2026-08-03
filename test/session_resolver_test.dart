import 'package:flutter_test/flutter_test.dart';
import 'package:preconnect/features/schedule/application/session_resolver.dart';
import 'package:preconnect/tools/app_storage.dart';
import 'package:preconnect/tools/storage_keys.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    resetCachedCurrentSessionSemesterId();
  });

  test(
    'resolves the persisted semester id without hitting the network',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        StorageKeys.currentSessionSemesterId: '20263',
      });
      await AppStorage.initialize();

      expect(await resolveCurrentSessionSemesterId(), 20263);
    },
  );

  test(
    'resetCachedCurrentSessionSemesterId clears the in-memory shortcut so a '
    'newly persisted semester id is picked up instead of a stale one',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        StorageKeys.currentSessionSemesterId: '20263',
      });
      await AppStorage.initialize();
      expect(await resolveCurrentSessionSemesterId(), 20263);

      await AppStorage.instance.setString(
        StorageKeys.currentSessionSemesterId,
        '20271',
      );
      expect(await resolveCurrentSessionSemesterId(), 20263);

      resetCachedCurrentSessionSemesterId();

      expect(await resolveCurrentSessionSemesterId(), 20271);
    },
  );
}
