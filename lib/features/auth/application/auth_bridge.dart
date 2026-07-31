typedef OpenLogoutView = Future<bool> Function(String idToken);
typedef ClearUiArtifacts = Future<void> Function();
typedef CompleteLogout = Future<void> Function();

class AuthUiBridge {
  AuthUiBridge._();

  static OpenLogoutView? _openLogoutView;
  static ClearUiArtifacts? _clearLoginArtifacts;
  static ClearUiArtifacts? _clearPrinterArtifacts;
  static CompleteLogout? _completeLogout;

  static void configure({
    required OpenLogoutView openLogoutView,
    required ClearUiArtifacts clearLoginArtifacts,
    required ClearUiArtifacts clearPrinterArtifacts,
    required CompleteLogout completeLogout,
  }) {
    _openLogoutView = openLogoutView;
    _clearLoginArtifacts = clearLoginArtifacts;
    _clearPrinterArtifacts = clearPrinterArtifacts;
    _completeLogout = completeLogout;
  }

  static Future<bool> openLogoutView(String idToken) async {
    final handler = _openLogoutView;
    return handler == null ? false : handler(idToken);
  }

  static Future<void> clearSessionArtifacts() async {
    await _clearLoginArtifacts?.call();
    await _clearPrinterArtifacts?.call();
  }

  static Future<void> completeLogout() async {
    await _completeLogout?.call();
  }
}
