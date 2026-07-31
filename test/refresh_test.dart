import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:preconnect/tools/token_refresh.dart';

void main() {
  group('refreshBracuSessionTokens', () {
    test('persists a complete successful refresh', () async {
      String? persistedAccess;
      String? persistedRefresh;
      String? persistedId;
      var clearCount = 0;
      final client = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.bodyFields['grant_type'], 'refresh_token');
        expect(request.bodyFields['refresh_token'], 'old-refresh');
        return http.Response(
          '{"access_token":"new-access","refresh_token":"new-refresh",'
          '"id_token":"new-id"}',
          200,
        );
      });

      final status = await refreshBracuSessionTokens(
        refreshToken: 'old-refresh',
        client: client,
        persistTokens: (access, refresh, id) async {
          persistedAccess = access;
          persistedRefresh = refresh;
          persistedId = id;
        },
        clearTokens: () async => clearCount++,
      );

      expect(status, TokenRefreshStatus.refreshed);
      expect(persistedAccess, 'new-access');
      expect(persistedRefresh, 'new-refresh');
      expect(persistedId, 'new-id');
      expect(clearCount, 0);
    });

    test('clears tokens when the server rejects the refresh token', () async {
      var clearCount = 0;
      final status = await refreshBracuSessionTokens(
        refreshToken: 'expired',
        client: MockClient((_) async => http.Response('invalid', 401)),
        persistTokens: (_, _, _) async {},
        clearTokens: () async => clearCount++,
      );

      expect(status, TokenRefreshStatus.invalidSession);
      expect(clearCount, 1);
    });

    test('keeps tokens for retryable server and network failures', () async {
      var clearCount = 0;
      final serverFailure = await refreshBracuSessionTokens(
        refreshToken: 'refresh',
        client: MockClient((_) async => http.Response('unavailable', 503)),
        persistTokens: (_, _, _) async {},
        clearTokens: () async => clearCount++,
      );
      final networkFailure = await refreshBracuSessionTokens(
        refreshToken: 'refresh',
        client: MockClient((_) async => throw Exception('offline')),
        persistTokens: (_, _, _) async {},
        clearTokens: () async => clearCount++,
      );

      expect(serverFailure, TokenRefreshStatus.retryableFailure);
      expect(networkFailure, TokenRefreshStatus.retryableFailure);
      expect(clearCount, 0);
    });
  });
}
