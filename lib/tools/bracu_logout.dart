import 'package:preconnect/api/api_config.dart';

class BracuLogout {
  BracuLogout._();

  static const String redirectUri = '${ApiConfig.connectOrigin}/';

  static Uri ssoLogoutUri({String? idToken}) {
    final cleanedIdToken = idToken?.trim() ?? '';
    return Uri.parse(ApiConfig.logoutEndpoint).replace(
      queryParameters: <String, String>{
        'client_id': ApiConfig.clientId,
        'post_logout_redirect_uri': redirectUri,
        if (cleanedIdToken.isNotEmpty) 'id_token_hint': cleanedIdToken,
      },
    );
  }

  static Uri get mercureLogoutUri => Uri.parse(
    '${ApiConfig.connectWebApiBase}${ApiConfig.connectMercureLogoutPath}',
  );

  static Map<String, String> mercureLogoutHeaders({String? accessToken}) {
    final cleanedAccessToken = accessToken?.trim() ?? '';
    return <String, String>{
      ...ApiConfig.apiHeaders,
      if (cleanedAccessToken.isNotEmpty)
        'Authorization': 'Bearer $cleanedAccessToken',
    };
  }

  static bool isConnectLogoutRedirect(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    if (uri.scheme != 'https' || uri.host != 'connect.bracu.ac.bd') {
      return false;
    }
    return uri.path.isEmpty ||
        uri.path == '/' ||
        uri.path.contains('/student/profile/overview');
  }
}
