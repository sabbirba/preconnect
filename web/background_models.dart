part of 'background.dart';

class _PendingLogin {
  const _PendingLogin({
    required this.tabId,
    required this.verifier,
    required this.startedAtMillis,
  });

  final int tabId;
  final String verifier;
  final int startedAtMillis;

  Map<String, Object> toJson() => {
    'tabId': tabId,
    'verifier': verifier,
    'startedAtMillis': startedAtMillis,
  };

  static _PendingLogin? fromJson(Object? value) {
    if (value is! Map) return null;
    final tabId = int.tryParse('${value['tabId'] ?? ''}');
    final verifier = '${value['verifier'] ?? ''}';
    final startedAtMillis = int.tryParse('${value['startedAtMillis'] ?? ''}');
    if (tabId == null || verifier.isEmpty || startedAtMillis == null) {
      return null;
    }
    return _PendingLogin(
      tabId: tabId,
      verifier: verifier,
      startedAtMillis: startedAtMillis,
    );
  }
}

class _PendingLogout {
  const _PendingLogout({
    required this.appTabId,
    required this.logoutTabId,
    required this.startedAtMillis,
  });

  final int? appTabId;
  final int logoutTabId;
  final int startedAtMillis;

  Map<String, Object?> toJson() => {
    'appTabId': appTabId,
    'logoutTabId': logoutTabId,
    'startedAtMillis': startedAtMillis,
  };

  static _PendingLogout? fromJson(Object? value) {
    if (value is! Map) return null;
    final logoutTabId = int.tryParse('${value['logoutTabId'] ?? ''}');
    final startedAtMillis = int.tryParse('${value['startedAtMillis'] ?? ''}');
    final appTabIdValue = value['appTabId'];
    final appTabId = appTabIdValue == null
        ? null
        : int.tryParse('$appTabIdValue');
    if (logoutTabId == null || startedAtMillis == null) return null;
    return _PendingLogout(
      appTabId: appTabId,
      logoutTabId: logoutTabId,
      startedAtMillis: startedAtMillis,
    );
  }
}

class _TokenResponse {
  const _TokenResponse({
    required this.accessToken,
    required this.refreshToken,
    required this.idToken,
  });

  final String accessToken;
  final String refreshToken;
  final String idToken;
}
