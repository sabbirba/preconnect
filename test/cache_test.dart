import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:preconnect/api/api_client.dart';
import 'package:preconnect/api/custom_schedules.dart';
import 'package:preconnect/api/exam_map.dart';
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

  test(
    'GET caches distinguish authentication and preserve bypass requests',
    () async {
      var requests = 0;
      final client = ApiClient.testing(
        MockClient((request) async {
          requests++;
          return http.Response(
            request.headers['Authorization'] ?? 'public',
            200,
          );
        }),
      );
      const url = 'https://example.test/data';
      expect(
        (await client.publicGet(
          url,
          headers: {'Authorization': 'synthetic_first'},
        )).body,
        'synthetic_first',
      );
      expect(
        (await client.publicGet(
          url,
          headers: {'Authorization': 'synthetic_second'},
        )).body,
        'synthetic_second',
      );
      await client.publicGet(
        url,
        headers: {'Authorization': 'synthetic_first'},
      );
      expect(requests, 2);
      await client.authenticatedGet(url);
      await client.authenticatedGet(url, bypassCache: true);
      expect(requests, 4);
    },
  );

  test(
    'forced refreshes revalidate with ETags and keep non-Latin bodies on 304',
    () async {
      const body = '[{"title":"নোটিশ “Fall 2026”"}]';
      final sentEtags = <String?>[];
      final client = ApiClient.testing(
        MockClient((request) async {
          sentEtags.add(request.headers['If-None-Match']);
          if (request.headers['If-None-Match'] == 'W/"v1"') {
            return http.Response('', 304, headers: {'etag': 'W/"v1"'});
          }
          return http.Response.bytes(
            utf8.encode(body),
            200,
            headers: {
              'etag': 'W/"v1"',
              'content-type': 'application/json; charset=utf-8',
            },
          );
        }),
      );
      const url = 'https://api.preconnect.app/announcements.json';
      expect((await client.publicGet(url)).body, body);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final revalidated = await client.publicGet(
        url,
        cacheDuration: Duration.zero,
      );
      expect(sentEtags, [null, 'W/"v1"']);
      expect(revalidated.statusCode, 200);
      expect(revalidated.body, body);
      expect(revalidated.headers['etag'], 'W/"v1"');
    },
  );

  test('requests around a stored ETag share one in-flight request', () async {
    const url = 'https://api.preconnect.app/example.json';
    final response = Completer<http.Response>();
    final sentEtags = <String?>[];
    final client = ApiClient.testing(
      MockClient((request) {
        sentEtags.add(request.headers['If-None-Match']);
        return response.future;
      }),
    );
    final first = client.publicGet(url, cacheDuration: Duration.zero);
    await AppStorage.instance.setString('etag_$url', 'W/"v1"');
    await AppStorage.instance.setString('etag_resp_$url', '{"label":"old"}');
    final second = client.publicGet(url, cacheDuration: Duration.zero);
    response.complete(
      http.Response('{"label":"fresh"}', 200, headers: {'etag': 'W/"v2"'}),
    );
    final bodies = (await Future.wait([first, second])).map((r) => r.body);
    expect(bodies, ['{"label":"fresh"}', '{"label":"fresh"}']);
    expect(sentEtags, [null]);
  });

  test('requests joining a revalidation receive the cached body', () async {
    const url = 'https://api.preconnect.app/example.json';
    await AppStorage.instance.setString('etag_$url', 'W/"v1"');
    await AppStorage.instance.setString('etag_resp_$url', '{"label":"kept"}');
    final response = Completer<http.Response>();
    var requests = 0;
    final client = ApiClient.testing(
      MockClient((_) {
        requests++;
        return response.future;
      }),
    );
    final first = client.publicGet(url, cacheDuration: Duration.zero);
    final second = client.publicGet(url, cacheDuration: Duration.zero);
    await Future<void>.delayed(Duration.zero);
    response.complete(http.Response('', 304, headers: {'etag': 'W/"v1"'}));
    final results = await Future.wait([first, second]);
    expect(results.map((r) => r.statusCode), [200, 200]);
    expect(results.map((r) => r.body), [
      '{"label":"kept"}',
      '{"label":"kept"}',
    ]);
    expect(requests, 1);
  });

  test(
    'shared exam files are fetched once and not revalidated again',
    () async {
      const indexUrl = 'https://api.preconnect.app/exammap.json';
      const examUrl = 'https://api.preconnect.app/pdf/example/exam.json';
      final requests = <String>[];
      ApiClient.testOverride = ApiClient.testing(
        MockClient((request) async {
          final url = request.url.toString();
          requests.add(url);
          if (url == indexUrl) {
            return http.Response(
              jsonEncode([
                {'exam_name': 'Fall 2026 Final', 'url': examUrl},
              ]),
              200,
            );
          }
          return http.Response(
            jsonEncode({
              'exams': [
                {
                  'Course': 'EXAMPLE101',
                  'Section': '01',
                  'Date': '2026-12-01',
                  'Start Time': '08:00',
                  'End Time': '10:00',
                  'Room': 'EXAMPLE-ROOM',
                },
              ],
            }),
            200,
          );
        }),
      );
      addTearDown(() => ApiClient.testOverride = null);
      final service = ExamMapService();
      final overrides = await service.getOverridesForSemester(
        semesterSessionId: 20263,
        forceRefresh: true,
      );
      expect(overrides['EXAMPLE101|1']?.finalRoomNumber, 'EXAMPLE-ROOM');
      expect(requests.where((url) => url == examUrl), hasLength(1));
      await service.getOverridesForSemester(semesterSessionId: 20263);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(requests, [indexUrl, examUrl]);
    },
  );

  test('invalidated in-flight requests cannot repopulate the cache', () async {
    final oldResponse = Completer<http.Response>();
    var requests = 0;
    final client = ApiClient.testing(
      MockClient((_) {
        requests++;
        return requests == 1
            ? oldResponse.future
            : Future.value(http.Response('fresh', 200));
      }),
    );
    final old = client.publicGet('https://example.test/data');
    await Future<void>.delayed(Duration.zero);
    client.clearTransientCaches();
    expect((await client.publicGet('https://example.test/data')).body, 'fresh');
    oldResponse.complete(http.Response('old', 200));
    await old;
    expect((await client.publicGet('https://example.test/data')).body, 'fresh');
    expect(requests, 2);
  });

  test(
    'temporary refresh failures keep the session distinct from revocation',
    () async {
      for (final status in [
        TokenRefreshStatus.retryableFailure,
        TokenRefreshStatus.invalidSession,
      ]) {
        final client = ApiClient.testing(
          MockClient((_) async => http.Response('unauthorized', 401)),
          refresh: () async => status,
        );
        await expectLater(
          client.authenticatedGet('https://example.test/data'),
          throwsA(
            status == TokenRefreshStatus.invalidSession
                ? isA<SessionExpiredException>()
                : isA<SessionRefreshException>(),
          ),
        );
      }
    },
  );

  test('overlapping custom schedule creation preserves both items', () async {
    final service = CustomSchedulesService();
    final now = DateTime.now().add(const Duration(days: 1));
    final items = await Future.wait([
      service.createItem(
        kind: 'event',
        title: 'Example One',
        startTime: now,
        endTime: now.add(const Duration(hours: 1)),
      ),
      service.createItem(
        kind: 'event',
        title: 'Example Two',
        startTime: now,
        endTime: now.add(const Duration(hours: 2)),
      ),
    ]);
    expect(items.map((item) => item.itemId).toSet(), hasLength(2));
    expect(await service.getCachedItems(), hasLength(2));
    final plan = await QuietModeSchedulePlanner().buildPlan();
    expect(plan.windows, hasLength(1));
    expect(plan.windows.single.endAt, now.add(const Duration(hours: 2)));
  });
}
