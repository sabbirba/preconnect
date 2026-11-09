import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:preconnect/api/api_client.dart';
import 'package:preconnect/api/notification.dart';
import 'package:preconnect/api/repository_cache.dart';
import 'package:preconnect/tools/app_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  final viewed = <String>[];

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('preconnect_unread_');
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({
      'access_token': 'synthetic_access',
    });
    await AppStorage.initialize(cacheDirectory: directory);
    viewed.clear();
    ApiClient.testOverride = ApiClient.testing(
      MockClient((request) async {
        final path = request.url.path;
        if (path.contains('/ns/notifications/view/')) {
          viewed.add(path.split('/').last);
          return http.Response(jsonEncode({'id': 0, 'title': 'Seen'}), 200);
        }
        return http.Response('{}', 200);
      }),
    );
  });

  tearDown(() async {
    ApiClient.testOverride = null;
    await directory.delete(recursive: true);
  });

  test('mark all seen reads every unseen Connect notification', () async {
    await RepositoryCache.instance.writeJson('RecentNotificationsFeed', {
      'new': 2,
      'items': [
        {'id': 1, 'title': 'Old', 'seen': true},
        {'id': 2, 'title': 'New one', 'seen': false},
        {'id': 3, 'title': 'New two', 'seen': false},
      ],
    });
    final updated = await NotificationService().markAllSeen();
    expect(viewed..sort(), ['2', '3']);
    expect(updated?.newCount, 0);
    expect(updated?.items.every((item) => item.seen), isTrue);
  });
}
