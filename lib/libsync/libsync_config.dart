import 'dart:convert';

class LibSyncConfig {
  LibSyncConfig._();

  static const String apiBaseUrl = 'https://libsync.bracu.ac.bd';
  static const String authSocialGoogleUrl =
      '$apiBaseUrl/api/user/auth/social/google/';
  static const String userMeUrl = '$apiBaseUrl/api/user/me/';
  static const String tokenRefreshUrl =
      '$apiBaseUrl/api/user/auth/token/refresh/';

  static final String googleClientId = utf8.decode(
    base64.decode(
      '=02bj5CduVGdu92YyV2c1VGbn92bn5ycwBXYukma3UmNzdzZnx2NqpGdvNnYhRzZwYTYvVDajNncntmctYzMxEDN5gDM1MTN'
          .split('')
          .reversed
          .join(),
    ),
  );
  static final String googleClientSecret = utf8.decode(
    base64.decode(
      '=s0TwVnaTJ1Znt2bplmczp0X4YmRChVVNRGaZFWLYB1UD90R'
          .split('')
          .reversed
          .join(),
    ),
  );
  static const String googleRedirectUri =
      'https://preconnect.app/api/auth/callback';
  static const String googleNativeRedirectUri = 'preconnect://callback';
  static const String googleScopes = 'openid email profile';

  static Uri buildOAuthUrl({
    required String redirectUri,
    bool includeState = true,
  }) {
    return Uri.parse('https://accounts.google.com/o/oauth2/v2/auth').replace(
      queryParameters: {
        'client_id': googleClientId,
        'redirect_uri': redirectUri,
        'response_type': 'code',
        'scope': googleScopes,
        'access_type': 'offline',
        'prompt': 'consent',
        if (includeState) 'state': 'app',
      },
    );
  }
}
