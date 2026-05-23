import 'dart:convert';

import 'package:preconnect/api/http_service.dart';
import 'package:preconnect/tools/web_extension_api_config.dart';

enum TokenRefreshStatus { refreshed, invalidSession, retryableFailure }

Future<TokenRefreshStatus> refreshBracuSessionTokens({
  required String refreshToken,
  required Future<void> Function(String accessToken, String refreshToken)
  persistTokens,
  required Future<void> Function() clearTokens,
  Duration timeout = const Duration(seconds: 12),
}) async {
  final cleanedRefreshToken = refreshToken.trim();
  if (cleanedRefreshToken.isEmpty) {
    return TokenRefreshStatus.invalidSession;
  }

  try {
    final response = await HttpService.client
        .post(
          Uri.parse(WebExtensionApiConfig.tokenEndpoint),
          headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
          body: {
            'grant_type': 'refresh_token',
            'refresh_token': cleanedRefreshToken,
            'client_id': WebExtensionApiConfig.clientId,
          },
        )
        .timeout(timeout);

    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return TokenRefreshStatus.invalidSession;
      }

      final newAccessToken = '${decoded['access_token'] ?? ''}'.trim();
      final newRefreshToken = '${decoded['refresh_token'] ?? ''}'.trim();
      if (newAccessToken.isEmpty || newRefreshToken.isEmpty) {
        return TokenRefreshStatus.invalidSession;
      }

      await persistTokens(newAccessToken, newRefreshToken);
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
