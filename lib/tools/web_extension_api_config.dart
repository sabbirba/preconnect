import 'package:preconnect/api/api_config.dart';

class WebExtensionApiConfig {
  WebExtensionApiConfig._();

  static const String ssoBase =
      'https://sso.bracu.ac.bd/realms/bracu/protocol/openid-connect';
  static const String tokenEndpoint = '$ssoBase/token';
  static const String authEndpoint = '$ssoBase/auth';
  static const String clientId = 'slm';
  static const String redirectUri = ApiConfig.redirectUri;

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
