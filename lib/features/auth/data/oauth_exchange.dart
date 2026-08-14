import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/tools/app_log.dart';
import 'package:preconnect/tools/http/http_utils.dart';
import 'package:preconnect/tools/preconnect_constants.dart';
import 'package:preconnect/tools/token_storage.dart';

class AuthTokens {
  const AuthTokens({
    required this.accessToken,
    required this.refreshToken,
    this.idToken,
  });

  final String accessToken;
  final String refreshToken;
  final String? idToken;
}

class OAuthCodeExchangeException implements Exception {
  const OAuthCodeExchangeException(this.message);

  final String message;

  @override
  String toString() => 'OAuthCodeExchangeException: $message';
}

class OAuthCodeExchange {
  OAuthCodeExchange({http.Client? client})
    : _client = client ?? HttpUtils.client;

  final http.Client _client;

  Future<AuthTokens> exchange({
    required String code,
    String? verifier,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final normalizedCode = code.trim();
    if (normalizedCode.isEmpty) {
      throw const OAuthCodeExchangeException('Authorization code is missing.');
    }

    final uri = Uri.parse(ApiConfig.tokenEndpoint);
    final normalizedVerifier = verifier?.trim() ?? '';
    final http.Response response;
    try {
      response = await _client
          .post(
            uri,
            headers: <String, String>{
              'Content-Type': 'application/x-www-form-urlencoded',
            },
            body: HttpUtils.formBody(<String, String>{
              'grant_type': 'authorization_code',
              'client_id': ApiConfig.clientId,
              'code': normalizedCode,
              'redirect_uri': ApiConfig.redirectUri,
              if (normalizedVerifier.isNotEmpty)
                'code_verifier': normalizedVerifier,
            }),
          )
          .timeout(timeout);
    } catch (e) {
      unawaited(
        AppLog.write('OAuth PKCE Error: Network failure during exchange ($e)'),
      );
      rethrow;
    }

    if (response.statusCode != 200) {
      unawaited(
        AppLog.write(
          'OAuth PKCE Error: Token endpoint returned HTTP ${response.statusCode}',
        ),
      );
      throw OAuthCodeExchangeException(
        'Token endpoint returned HTTP ${response.statusCode}.',
      );
    }

    final dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw const OAuthCodeExchangeException(
        'Token endpoint returned malformed JSON.',
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw const OAuthCodeExchangeException(
        'Token endpoint returned an invalid payload.',
      );
    }

    final accessToken = '${decoded['access_token'] ?? ''}'.trim();
    final refreshToken = '${decoded['refresh_token'] ?? ''}'.trim();
    final idToken = '${decoded['id_token'] ?? ''}'.trim();
    if (accessToken.isEmpty || refreshToken.isEmpty) {
      throw const OAuthCodeExchangeException(
        'Token endpoint omitted required tokens.',
      );
    }

    unawaited(
      AppLog.write(
        'OAuth PKCE: Successfully exchanged authorization code for session tokens',
      ),
    );

    return AuthTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
      idToken: idToken.isEmpty ? null : idToken,
    );
  }

  Future<void> persist(AuthTokens tokens) async {
    await TokenStorage.instance.write(
      key: PreConnectStorageKeys.accessToken,
      value: tokens.accessToken,
    );
    await TokenStorage.instance.write(
      key: PreConnectStorageKeys.refreshToken,
      value: tokens.refreshToken,
    );
    await TokenStorage.instance.write(
      key: PreConnectStorageKeys.idToken,
      value: tokens.idToken,
    );
  }

  Future<AuthTokens> exchangeAndPersist({
    required String code,
    String? verifier,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final tokens = await exchange(
      code: code,
      verifier: verifier,
      timeout: timeout,
    );
    await persist(tokens);
    return tokens;
  }
}
