import 'package:preconnect/api/api_config.dart';

class WebExtensionApiConfig {
  WebExtensionApiConfig._();

  static const String tokenEndpoint = '${ApiConfig.ssoBase}/token';
  static const String authEndpoint = '${ApiConfig.ssoBase}/auth';
  static const String clientId = ApiConfig.clientId;
  static const String redirectUri =
      '${ApiConfig.connectOrigin}/student/profile/overview';

  static String authUrlWithPkce(String codeChallenge) {
    return ApiConfig.pkceAuthUrl(
      endpoint: authEndpoint,
      clientId: clientId,
      redirectUri: redirectUri,
      codeChallenge: codeChallenge,
    );
  }
}
