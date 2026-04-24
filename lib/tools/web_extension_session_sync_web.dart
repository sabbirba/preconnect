import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:preconnect/tools/web_extension_api_config.dart';
import 'package:preconnect/tools/web_extension_token_storage.dart';

const Duration _refreshLeadTime = Duration(minutes: 5);

Future<bool> ensureFreshWebExtensionSession({
  bool forceRefresh = false,
}) async {
  final storage = WebExtensionTokenStorage.instance;
  final accessToken = await storage.read(key: 'access_token');
  final refreshToken = await storage.read(key: 'refresh_token');
  if (refreshToken == null || refreshToken.trim().isEmpty) {
    return false;
  }

  if (!forceRefresh && accessToken != null && accessToken.isNotEmpty) {
    final expiresAt = _jwtExpiry(accessToken);
    if (expiresAt != null &&
        DateTime.now().isBefore(expiresAt.subtract(_refreshLeadTime))) {
      return true;
    }
  }

  final response = await http.post(
    Uri.parse(WebExtensionApiConfig.tokenEndpoint),
    headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
    body: {
      'grant_type': 'refresh_token',
      'refresh_token': refreshToken,
      'client_id': WebExtensionApiConfig.clientId,
    },
  );

  if (response.statusCode != 200) {
    if (response.statusCode == 400 || response.statusCode == 401) {
      await storage.deleteAll();
    }
    return false;
  }

  final decoded = jsonDecode(response.body);
  if (decoded is! Map<String, dynamic>) {
    return false;
  }

  final newAccessToken = '${decoded['access_token'] ?? ''}'.trim();
  final newRefreshToken = '${decoded['refresh_token'] ?? ''}'.trim();
  if (newAccessToken.isEmpty || newRefreshToken.isEmpty) {
    return false;
  }

  await storage.write(key: 'access_token', value: newAccessToken);
  await storage.write(key: 'refresh_token', value: newRefreshToken);
  return true;
}

DateTime? _jwtExpiry(String token) {
  try {
    final parts = token.split('.');
    if (parts.length != 3) return null;
    final payload = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
    );
    if (payload is! Map) return null;
    final exp = payload['exp'];
    if (exp == null) return null;
    final seconds = int.tryParse('$exp');
    if (seconds == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
  } catch (_) {
    return null;
  }
}
