import 'package:preconnect/api/api_config.dart';

class WebExtensionApiConfig {
  WebExtensionApiConfig._();

  static const String tokenEndpoint = ApiConfig.tokenEndpoint;
  static const String authEndpoint = ApiConfig.authEndpoint;
  static const String clientId = ApiConfig.clientId;
  static const String redirectUri =
      '${ApiConfig.connectOrigin}/student/profile/overview';

  static String authUrlWithPkce(String codeChallenge) {
    final encodedChallenge = Uri.encodeQueryComponent(codeChallenge);
    return '$authEndpoint'
        '?client_id=$clientId'
        '&redirect_uri=${Uri.encodeQueryComponent(redirectUri)}'
        '&response_type=code'
        '&response_mode=query'
        '&scope=openid offline_access'
        '&code_challenge=$encodedChallenge'
        '&code_challenge_method=S256';
  }
}
