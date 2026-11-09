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
        if (path.endsWith('/ns/notifications/user')) {
          final offset = int.parse(request.url.queryParameters['offset']!);
          final rows = [
            for (var id = 1; id <= 150; id++)
              {'id': id, 'seen': id != 3 && id != 120},
          ];
          return http.Response(
            jsonEncode({
              'rows': rows.skip(offset).take(100).toList(),
              'lastRow': rows.length,
            }),
            200,
          );
        }
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

  test('mark all seen reads every unseen notification on every page', () async {
    await RepositoryCache.instance.writeJson('RecentNotificationsFeed', {
      'new': 3,
      'items': [
        {'id': 1, 'title': 'Old', 'seen': true},
        {'id': 3, 'title': 'New', 'seen': false},
        {'id': 200, 'title': 'Newest', 'seen': false},
      ],
    });
    final updated = await NotificationService().markAllSeen();
    expect(viewed..sort(), ['120', '200', '3']);
    expect(updated?.newCount, 0);
    expect(updated?.items.every((item) => item.seen), isTrue);
  });
}
