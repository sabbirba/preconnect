import 'package:flutter_test/flutter_test.dart';
import 'package:preconnect/tools/storage_web.dart';
import 'package:web/web.dart' as web;

void main() {
  const key = 'preconnect_test_storage';
  tearDown(() async => webExtensionStorageRemoveKeys([key]));

  test(
    'enumeration restores session values and prefers local values',
    () async {
      web.window.sessionStorage.setItem(key, 'session');
      expect((await webExtensionStorageGetAll())[key], 'session');
      web.window.localStorage.setItem(key, 'local');
      expect((await webExtensionStorageGetAll())[key], 'local');
      await webExtensionStorageSet(key, null);
      expect(await webExtensionStorageGet(key), isNull);
      expect(web.window.sessionStorage.getItem(key), isNull);
    },
  );
}
