import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/tools/app_log.dart';
import 'package:preconnect/tools/http/http_utils.dart';
import 'package:preconnect/tools/extension_config.dart';

enum TokenRefreshStatus { refreshed, invalidSession, retryableFailure }

Future<TokenRefreshStatus> refreshBracuSessionTokens({
  required String refreshToken,
  required Future<void> Function(
    String accessToken,
    String refreshToken,
    String? idToken,
  )
  persistTokens,
  required Future<void> Function() clearTokens,
  Duration timeout = const Duration(seconds: 12),
  http.Client? client,
}) async {
  final cleanedRefreshToken = refreshToken.trim();
  if (cleanedRefreshToken.isEmpty) {
    return TokenRefreshStatus.invalidSession;
  }

  try {
    final uri = Uri.parse(ApiConfig.tokenEndpoint);
    final body = HttpUtils.formBody(<String, String>{
      'grant_type': 'refresh_token',
      'refresh_token': cleanedRefreshToken,
      'client_id': WebExtensionApiConfig.clientId,
      'scope': 'openid offline_access',
    });
    final response = await (client ?? HttpUtils.client)
        .post(
          uri,
          headers: <String, String>{
            'Content-Type': 'application/x-www-form-urlencoded',
          },
          body: body,
        )
        .timeout(timeout);

    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return TokenRefreshStatus.invalidSession;
      }

      final newAccessToken = '${decoded['access_token'] ?? ''}'.trim();
      final newRefreshToken = '${decoded['refresh_token'] ?? ''}'.trim();
      final newIdToken = '${decoded['id_token'] ?? ''}'.trim();
      if (newAccessToken.isEmpty || newRefreshToken.isEmpty) {
        return TokenRefreshStatus.invalidSession;
      }

      await persistTokens(
        newAccessToken,
        newRefreshToken,
        newIdToken.isEmpty ? null : newIdToken,
      );
      unawaited(AppLog.write('Auth Token Refresh: Successfully refreshed'));
      return TokenRefreshStatus.refreshed;
    }

    if (response.statusCode == 400 || response.statusCode == 401) {
      await clearTokens();
      unawaited(
        AppLog.write(
          'Auth Token Refresh: Session expired (${response.statusCode})',
        ),
      );
      return TokenRefreshStatus.invalidSession;
    }

    unawaited(
      AppLog.write(
        'Auth Token Refresh: Server returned status ${response.statusCode}',
      ),
    );
    return TokenRefreshStatus.retryableFailure;
  } catch (error) {
    unawaited(
      AppLog.write('Auth Token Refresh: Network/Retryable failure ($error)'),
    );
    return TokenRefreshStatus.retryableFailure;
  }
}
