import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:preconnect/features/auth/data/oauth_exchange.dart';

void main() {
  group('OAuthCodeExchange', () {
    test('parses all tokens from a successful response', () async {
      final client = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.bodyFields['code'], 'authorization-code');
        expect(request.bodyFields['code_verifier'], 'pkce-verifier');
        return http.Response(
          '{"access_token":"access","refresh_token":"refresh",'
          '"id_token":"identity"}',
          200,
        );
      });

      final tokens = await OAuthCodeExchange(
        client: client,
      ).exchange(code: 'authorization-code', verifier: 'pkce-verifier');

      expect(tokens.accessToken, 'access');
      expect(tokens.refreshToken, 'refresh');
      expect(tokens.idToken, 'identity');
    });

    test('rejects malformed and incomplete responses explicitly', () async {
      final malformed = OAuthCodeExchange(
        client: MockClient((_) async => http.Response('not-json', 200)),
      );
      final incomplete = OAuthCodeExchange(
        client: MockClient(
          (_) async => http.Response('{"access_token":"access"}', 200),
        ),
      );

      await expectLater(
        malformed.exchange(code: 'code'),
        throwsA(isA<OAuthCodeExchangeException>()),
      );
      await expectLater(
        incomplete.exchange(code: 'code'),
        throwsA(isA<OAuthCodeExchangeException>()),
      );
    });

    test('rejects an unsuccessful token endpoint response', () async {
      final exchange = OAuthCodeExchange(
        client: MockClient((_) async => http.Response('denied', 401)),
      );

      await expectLater(
        exchange.exchange(code: 'code'),
        throwsA(
          isA<OAuthCodeExchangeException>().having(
            (error) => error.message,
            'message',
            contains('401'),
          ),
        ),
      );
    });
  });
}
