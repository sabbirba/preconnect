import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:preconnect/libsync/auth_service.dart';
import 'package:preconnect/libsync/availability_response.dart';
import 'package:preconnect/libsync/libsync_client.dart';
import 'package:preconnect/tools/app_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Client extends LibSyncApiClient {
  Future<Map<String, String>> Function()? readCookies;
  Future<http.Response> Function()? readProfile;
  Object? saveError;
  Object? clearError;
  int requests = 0;
  int clears = 0;

  @override
  Future<Map<String, String>> getStoredCookies() async =>
      readCookies == null ? {} : readCookies!();

  @override
  Future<String?> getGoogleRefreshToken() async => null;

  @override
  Future<void> storeGoogleRefreshToken(String token) async {}

  @override
  Future<Map<String, dynamic>?> getCachedProfile() async => null;

  @override
  Future<void> saveCachedProfile(Map<String, dynamic> profile) async {
    if (saveError != null) throw saveError!;
  }

  @override
  Future<void> clearAuthData() async {
    clears++;
    if (clearError != null) throw clearError!;
  }

  @override
  Future<http.Response> post(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
  }) async {
    requests++;
    return http.Response('{"message":"refreshed"}', 200);
  }

  @override
  Future<http.Response> get(Uri url, {Map<String, String>? headers}) async {
    requests++;
    return readProfile == null
        ? http.Response('{"fullname":"Synthetic account"}', 200)
        : readProfile!();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('preconnect_libsync_');
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await AppStorage.initialize(cacheDirectory: directory);
  });
  tearDown(() async => directory.delete(recursive: true));

  test('initial storage failure exits loading', () async {
    final client = _Client()
      ..readCookies = () async => throw StateError('Storage unavailable');
    final auth = LibSyncAuthService.testing(client);
    await auth.initialize();
    expect(auth.state.value.status, LibSyncAuthStatus.error);
  });

  test(
    'stalled initialization times out and late completion cannot sign in',
    () async {
      final pending = Completer<Map<String, String>>();
      final client = _Client()..readCookies = () => pending.future;
      final auth = LibSyncAuthService.testing(
        client,
        authTimeout: const Duration(milliseconds: 10),
      );
      await auth.initialize();
      expect(auth.state.value.status, LibSyncAuthStatus.error);
      pending.complete({'access': 'synthetic'});
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(auth.state.value.status, LibSyncAuthStatus.error);
    },
  );

  test('old initialization cannot overwrite a newer login', () async {
    final pending = Completer<Map<String, String>>();
    final client = _Client()..readCookies = () => pending.future;
    final auth = LibSyncAuthService.testing(client);
    final initialization = auth.initialize();
    await auth.authenticateWithAccessToken('synthetic');
    pending.complete({});
    await initialization;
    expect(auth.state.value.status, LibSyncAuthStatus.authenticated);
  });

  test('HTTP 200 login still requires a valid authenticated profile', () async {
    final client = _Client()
      ..readProfile = () async => http.Response('{}', 401);
    final auth = LibSyncAuthService.testing(client);
    await auth.authenticateWithAccessToken('synthetic');
    expect(auth.state.value.status, LibSyncAuthStatus.error);
    expect(auth.state.value.profile, isNull);
    expect(client.clears, 0);
  });

  test('profile persistence failure shows error and allows retry', () async {
    final client = _Client()..saveError = StateError('Keychain unavailable');
    final auth = LibSyncAuthService.testing(client);
    await auth.authenticateWithAccessToken('synthetic');
    expect(auth.state.value.status, LibSyncAuthStatus.error);
    client.saveError = null;
    await auth.authenticateWithAccessToken('synthetic');
    expect(auth.state.value.status, LibSyncAuthStatus.authenticated);
  });

  test('logout storage failure exits loading', () async {
    final client = _Client()..clearError = StateError('Storage unavailable');
    final auth = LibSyncAuthService.testing(client);
    await auth.logout();
    expect(auth.state.value.status, LibSyncAuthStatus.error);
  });

  test('callback failure invalidates a pending login result', () async {
    final pending = Completer<http.Response>();
    final client = _Client()..readProfile = () => pending.future;
    final auth = LibSyncAuthService.testing(client);
    final login = auth.authenticateWithAccessToken('synthetic');
    await Future<void>.delayed(Duration.zero);
    auth.failAuthentication('Sign-in cancelled');
    pending.complete(http.Response('{"fullname":"Synthetic account"}', 200));
    await login;
    expect(auth.state.value.status, LibSyncAuthStatus.error);
    expect(auth.state.value.errorMessage, 'Sign-in cancelled');
  });

  test('invalid availability never reaches transport', () async {
    final client = _Client();
    final auth = LibSyncAuthService.testing(client);
    for (final values in [
      ['2026-10-26', '2026-10-26', 'undefined', '23:50:00', 1],
      ['2026-10-26', '2026-10-26', '00:00:00', '23:50:00', 0],
      ['2026-02-30', '2026-03-01', '00:00:00', '23:50:00', 1],
      ['2026-10-27', '2026-10-26', '00:00:00', '23:50:00', 1],
      ['2026-10-26', '2026-10-26', '23:50:00', '00:00:00', 1],
      ['2026-10-26', '2026-10-26', '24:00:00', '23:50:00', 1],
    ]) {
      await expectLater(
        auth.fetchCheckAvailability(
          startDate: values[0] as String,
          endDate: values[1] as String,
          startTime: values[2] as String,
          endTime: values[3] as String,
          capacity: values[4] as int,
        ),
        throwsA(isA<AvailabilityException>()),
      );
    }
    expect(client.requests, 0);
  });

  test('valid availability uses encoded named query parameters', () async {
    Uri? requested;
    final client = LibSyncApiClient(
      client: MockClient((request) async {
        requested = request.url;
        return http.Response('[]', 200);
      }),
    );
    final auth = LibSyncAuthService.testing(client);
    expect(
      await auth.fetchCheckAvailability(
        startDate: '2026-10-26',
        endDate: '2026-10-26',
        startTime: '00:00:00',
        endTime: '23:50:00',
        capacity: 1,
        library: 'Library & Study',
      ),
      isEmpty,
    );
    expect(requested!.queryParameters['library'], 'Library & Study');
    expect(requested!.queryParameters['capacity'], '1');
    await client.clearCache();
  });

  test('request deadline includes a stalled response body', () async {
    final body = StreamController<List<int>>();
    final client = LibSyncApiClient(
      requestTimeout: const Duration(milliseconds: 30),
      client: MockClient.streaming(
        (request, _) async => http.StreamedResponse(body.stream, 200),
      ),
    );
    await expectLater(
      client.post(Uri.parse('https://example.test/login')),
      throwsA(isA<TimeoutException>()),
    );
    await body.close();
    await client.clearCache();
  });

  test('HTTP 200 availability error is not treated as an empty result', () {
    expect(
      () => parseAvailabilityResponse(
        200,
        '{"error":"User passed invaild data."}',
      ),
      throwsA(isA<AvailabilityException>()),
    );
  });
}
