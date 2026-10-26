import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:preconnect/api/api_client.dart';
import 'package:preconnect/api/custom_schedules.dart';
import 'package:preconnect/tools/app_storage.dart';
import 'package:preconnect/tools/cdn_cache.dart';
import 'package:preconnect/tools/schedule_planner.dart';
import 'package:preconnect/tools/token_refresh.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('preconnect_cache_');
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({
      'access_token': 'synthetic_access',
    });
    await AppStorage.initialize(cacheDirectory: directory);
  });
  tearDown(() async => directory.delete(recursive: true));

  test('simultaneous forced CDN refreshes share one request', () async {
    final response = Completer<http.Response>();
    var requests = 0;
    final transport = MockClient((_) {
      requests++;
      return response.future;
    });
    Future<String?> load() => CdnJsonCache.load<String>(
      url: 'https://example.test/feed',
      cacheKey: 'test_feed',
      decode: (value) => value['label'] as String?,
      forceRefresh: true,
      client: transport,
    );
    final first = load();
    final second = load();
    await Future<void>.delayed(Duration.zero);
    response.complete(http.Response('{"label":"fresh"}', 200));
    expect(await Future.wait([first, second]), ['fresh', 'fresh']);
    expect(requests, 1);
  });


}
