class LibSyncConfig {
  LibSyncConfig._();

  static const String apiBaseUrl = 'https://libsync.bracu.ac.bd';
  static const String authSocialGoogleUrl =
      '$apiBaseUrl/api/user/auth/social/google/';
  static const String userMeUrl = '$apiBaseUrl/api/user/me/';
  static const String tokenRefreshUrl =
      '$apiBaseUrl/api/user/auth/token/refresh/';

  static const String googleClientId =
      '53508941136-rkgrsch5oa60g4absotjj7lgg7s6e7ji.apps.googleusercontent.com';
  static const String googleClientSecret = String.fromEnvironment(
    'GOOGLE_CLIENT_SECRET',
  );
  static const String googleRedirectUri =
      'https://preconnect.app/api/auth/callback';
  static const String googleScopes = 'openid email profile';
}
