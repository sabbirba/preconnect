import 'dart:convert';
import 'libsync_config.dart';
import 'client_creator.dart';

class GoogleAuthHelper {
  GoogleAuthHelper._();

  static Future<Map<String, dynamic>> refreshAccessToken(
    String refreshToken,
  ) async {
    final client = createLibSyncClient();
    try {
      final response = await client.post(
        Uri.parse('https://oauth2.googleapis.com/token'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'client_id': LibSyncConfig.googleClientId,
          'client_secret': LibSyncConfig.googleClientSecret,
          'refresh_token': refreshToken,
          'grant_type': 'refresh_token',
        },
      );

      if (response.statusCode != 200) throw Exception('Token refresh failed');

      final decoded = jsonDecode(response.body);
      if (decoded is Map) {
        return decoded.cast<String, dynamic>();
      }
      throw Exception('Invalid token refresh response');
    } finally {
      client.close();
    }
  }

  static Future<Map<String, dynamic>> exchangeCodeForTokens(
    String code, {
    String? redirectUri,
  }) async {
    final client = createLibSyncClient();
    try {
      final response = await client.post(
        Uri.parse('https://oauth2.googleapis.com/token'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'client_id': LibSyncConfig.googleClientId,
          'client_secret': LibSyncConfig.googleClientSecret,
          'code': code,
          'redirect_uri': redirectUri ?? LibSyncConfig.googleRedirectUri,
          'grant_type': 'authorization_code',
        },
      );

      if (response.statusCode != 200) throw Exception('Token exchange failed');

      final decoded = jsonDecode(response.body);
      if (decoded is Map) {
        return decoded.cast<String, dynamic>();
      }
      throw Exception('Invalid token exchange response');
    } finally {
      client.close();
    }
  }
}
