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
  final String? serverClientId;
  final List<String> scopes;
  GoogleSignIn({this.serverClientId, this.scopes = const []});
  Future<GoogleSignInAccount?> signIn() async => null;
  Future<GoogleSignInAccount?> signInSilently() async => null;
  Future<void> signOut() async {}
  Future<void> disconnect() async {}
}
