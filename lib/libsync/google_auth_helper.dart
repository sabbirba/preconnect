import 'dart:convert';
import 'package:http/http.dart' as http;
import 'libsync_config.dart';

class GoogleAuthHelper {
  GoogleAuthHelper._();

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

    if (response.statusCode != 200) throw Exception('Token refresh failed');

    return jsonDecode(response.body) as Map<String, dynamic>;
  }
}
