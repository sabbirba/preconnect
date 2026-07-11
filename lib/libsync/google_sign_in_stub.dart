class GoogleSignInAuthentication {
  final String? accessToken;
  GoogleSignInAuthentication({this.accessToken});
}

class GoogleSignInAccount {
  final String? serverAuthCode;
  final Future<GoogleSignInAuthentication>? authentication;
  GoogleSignInAccount({this.serverAuthCode, this.authentication});
}

class GoogleSignIn {
  GoogleSignIn._();
  static final GoogleSignIn instance = GoogleSignIn._();

  Future<void> initialize({
    String? clientId,
    String? serverClientId,
    String? hostedDomain,
    List<String> scopes = const [],
  }) async {}

  Future<GoogleSignInAccount?> authenticate() async => null;
  Future<GoogleSignInAccount?> attemptLightweightAuthentication() async => null;
  Future<void> signOut() async {}
  Future<void> disconnect() async {}
}
