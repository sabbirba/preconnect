import 'dart:convert';
import 'package:http/http.dart' as http;
import 'libsync_config.dart';

class GoogleAuthHelper {
  GoogleAuthHelper._();

  static String buildAuthorizationUrl() {
    final queryParams = {
      'client_id': LibSyncConfig.googleClientId,
      'redirect_uri': LibSyncConfig.googleRedirectUri,
      'response_type': 'code',
      'scope': LibSyncConfig.googleScopes,
      'access_type': 'offline',
      'prompt': 'consent',
    };
    final uri = Uri.https(
      'accounts.google.com',
      '/o/oauth2/v2/auth',
      queryParams,
    );
    return uri.toString();
  }

  static Future<Map<String, dynamic>> exchangeCode(String code) async {
    final response = await http.post(
      Uri.parse('https://oauth2.googleapis.com/token'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'code': code,
        'client_id': LibSyncConfig.googleClientId,
        'client_secret': LibSyncConfig.googleClientSecret,
        'redirect_uri': LibSyncConfig.googleRedirectUri,
        'grant_type': 'authorization_code',
      },
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to exchange Google OAuth code: ${response.body}');
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> refreshAccessToken(
    String refreshToken,
  ) async {
    final response = await http.post(
      Uri.parse('https://oauth2.googleapis.com/token'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'client_id': LibSyncConfig.googleClientId,
        'client_secret': LibSyncConfig.googleClientSecret,
        'refresh_token': refreshToken,
        'grant_type': 'refresh_token',
      },
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Failed to refresh Google access token: ${response.body}',
      );
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }
}
