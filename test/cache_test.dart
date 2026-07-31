import 'package:flutter_test/flutter_test.dart';
import 'package:preconnect/api/api_client.dart';
import 'package:preconnect/tools/app_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('clearing transient caches invalidates every in-memory API cache', () {
    final client = ApiClient()..seedTransientCachesForTesting();
    expect(client.hasTransientCachesForTesting, isTrue);

    client.clearTransientCaches();

    expect(client.hasTransientCachesForTesting, isFalse);
  });

  test('large preference values round-trip through the file cache', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await AppStorage.initialize();
    const key = 'large_cache_test';
    final value = List.filled(300 * 1024, 'x').join();

    await AppStorage.instance.setString(key, value);

    expect(await AppStorage.instance.getString(key), value);
    await AppStorage.instance.remove(key);
    expect(await AppStorage.instance.getString(key), isNull);
  });
}
