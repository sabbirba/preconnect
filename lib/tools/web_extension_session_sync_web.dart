import 'dart:convert';

import 'package:preconnect/api/api_client.dart';
import 'package:preconnect/tools/preconnect_constants.dart';
import 'package:preconnect/tools/token_refresh.dart';
import 'package:preconnect/tools/web_extension_token_storage.dart';

const Duration _refreshLeadTime = Duration(minutes: 5);

Future<bool> ensureFreshWebExtensionSession({bool forceRefresh = false}) async {
  final storage = WebExtensionTokenStorage.instance;
  final accessToken = await storage.read(
    key: PreconnectStorageKeys.accessToken,
  );
  final refreshToken = await storage.read(
    key: PreconnectStorageKeys.refreshToken,
  );
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

  final status = await refreshBracuSessionTokens(
    refreshToken: refreshToken,
    persistTokens: (accessToken, refreshToken) async {
      await storage.write(
        key: PreconnectStorageKeys.accessToken,
        value: accessToken,
      );
      await storage.write(
        key: PreconnectStorageKeys.refreshToken,
        value: refreshToken,
      );
      ApiClient().clearTransientCaches();
    },
    clearTokens: () async {
      await storage.deleteAll();
      ApiClient().clearTransientCaches();
    },
  );
  return status == TokenRefreshStatus.refreshed;
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
