class GoogleSignInClientAuthorization {
  final String? accessToken;
  GoogleSignInClientAuthorization({this.accessToken});
}

class GoogleSignInServerAuthorization {
  final String? serverAuthCode;
  GoogleSignInServerAuthorization({this.serverAuthCode});
}

class GoogleSignInAuthorizationClient {
  Future<GoogleSignInClientAuthorization?> authorizationForScopes(
    List<String> scopes,
  ) async => null;
  Future<GoogleSignInClientAuthorization?> authorizeScopes(
    List<String> scopes,
  ) async => null;
  Future<GoogleSignInServerAuthorization?> authorizeServer(
    List<String> scopes,
  ) async => null;
}

class GoogleSignInAccount {
  final GoogleSignInAuthorizationClient authorizationClient =
      GoogleSignInAuthorizationClient();
}

class GoogleSignIn {
  GoogleSignIn._();
  static final GoogleSignIn instance = GoogleSignIn._();

  Future<void> initialize({String? clientId, String? serverClientId}) async {}

  Future<GoogleSignInAccount?> authenticate() async => null;
  Future<GoogleSignInAccount?> attemptLightweightAuthentication() async => null;
  Future<void> signOut() async {}
  Future<void> disconnect() async {}
}
