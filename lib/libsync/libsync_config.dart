class LibSyncConfig {
  LibSyncConfig._();

  static const String apiBaseUrl = 'https://libsync.bracu.ac.bd';
  static const String authSocialGoogleUrl =
      '$apiBaseUrl/api/user/auth/social/google/';
  static const String userMeUrl = '$apiBaseUrl/api/user/me/';
  static const String tokenRefreshUrl =
      '$apiBaseUrl/api/user/auth/token/refresh/';

  static const String googleClientId = String.fromEnvironment(
    'GOOGLE_CLIENT_ID',
  );
  static const String googleClientSecret = String.fromEnvironment(
    'GOOGLE_CLIENT_SECRET',
  );
  static const String googleRedirectUri = String.fromEnvironment(
    'GOOGLE_REDIRECT_URI',
  );
  static const String googleScopes = String.fromEnvironment('GOOGLE_SCOPES');
}
