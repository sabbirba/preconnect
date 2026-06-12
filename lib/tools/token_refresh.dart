import 'dart:convert';

import 'package:preconnect/api/api_config.dart';
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
    final response = await HttpUtils.client
        .post(
          uri,
          headers: <String, String>{
            'Content-Type': 'application/x-www-form-urlencoded',
            ..._compressionHeadersForUri(uri),
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
      return TokenRefreshStatus.refreshed;
    }

    if (response.statusCode == 400 || response.statusCode == 401) {
      await clearTokens();
      return TokenRefreshStatus.invalidSession;
    }

    return TokenRefreshStatus.retryableFailure;
  } catch (_) {
    return TokenRefreshStatus.retryableFailure;
  }
}

Map<String, String> _compressionHeadersForUri(Uri? uri) {
  return const <String, String>{};
}
