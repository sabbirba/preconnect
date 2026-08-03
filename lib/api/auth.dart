import 'dart:async';
import 'dart:convert';
import 'package:preconnect/tools/http/http_utils.dart';
import 'package:preconnect/tools/http/http_headers.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/api/api_client.dart';
import 'package:preconnect/features/auth/application/auth_bridge.dart';
import 'package:preconnect/features/auth/application/session_cleanup.dart';
import 'package:preconnect/features/schedule/application/session_resolver.dart';
import 'package:preconnect/tools/bracu_logout.dart';
import 'package:preconnect/tools/cached_image.dart';
import 'package:preconnect/tools/preconnect_constants.dart';
import 'package:preconnect/tools/app_paths.dart';
import 'package:preconnect/tools/app_storage.dart';
import 'package:preconnect/tools/app_log.dart';
import 'package:preconnect/tools/token_refresh.dart';
import 'package:preconnect/tools/web_shared.dart';
import 'package:preconnect/tools/token_storage.dart';
import 'package:preconnect/libsync/auth_service.dart';
import 'package:preconnect/tools/refresh_bus.dart';
import 'package:preconnect/api/fcm.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal() {
    _bootstrapStartTime = DateTime.now();
  }

  final TokenStorage _storage = TokenStorage.instance;
  static const Duration _authRequestTimeout = Duration(seconds: 12);
  static Future<TokenRefreshStatus>? _tokenRefreshInFlight;

  static TokenRefreshStatus? _lastRefreshStatus;
  static DateTime? _lastRefreshTime;
  static const Duration _refreshResultTtl = Duration(seconds: 5);

  static DateTime? _bootstrapStartTime;
  static const Duration _bootstrapGracePeriod = Duration(seconds: 10);

  static bool _isLoggingOut = false;
  static bool get isLoggingOut => _isLoggingOut;

  Future<void> logout({
    bool instant = false,
    bool force = false,
    bool notify = true,
  }) async {
    if (_isLoggingOut) {
      return;
    }
    _isLoggingOut = true;

    try {
      if (!force && !instant && _bootstrapStartTime != null) {
        final timeSinceBootstrap = DateTime.now().difference(
          _bootstrapStartTime!,
        );
        if (timeSinceBootstrap < _bootstrapGracePeriod) {
          return;
        }
      }

      try {
        await FCMService.instance.unregisterDevice();
      } catch (error) {
        unawaited(AppLog.write('Push device unregistration failed: $error'));
      }

      var refreshToken = await _storage.read(
        key: PreConnectStorageKeys.refreshToken,
      );
      var accessToken = await _storage.read(
        key: PreConnectStorageKeys.accessToken,
      );
      var idToken = await _storage.read(key: PreConnectStorageKeys.idToken);
      if (accessToken == null && refreshToken == null) {
        await _clearAuthSessionData();
        await _clearLocalCaches();
        if (notify) {
          RefreshBus.instance.notify(reason: 'auth');
        }
        return;
      }

      if (!kIsWeb &&
          refreshToken != null &&
          refreshToken.isNotEmpty &&
          (idToken == null || idToken.isEmpty)) {
        await _performTokenRefresh();
        refreshToken = await _storage.read(
          key: PreConnectStorageKeys.refreshToken,
        );
        accessToken = await _storage.read(
          key: PreConnectStorageKeys.accessToken,
        );
        idToken = await _storage.read(key: PreConnectStorageKeys.idToken);
      }

      final canShowMobileLogoutWebView =
          !kIsWeb && idToken != null && idToken.isNotEmpty;
      if (canShowMobileLogoutWebView) {
        await _revokeMercureSession(accessToken);
        final opened = await AuthUiBridge.openLogoutView(idToken);
        if (opened) {
          await _clearAuthSessionData();
          await _clearLocalCaches();
          if (notify) {
            RefreshBus.instance.notify(reason: 'auth');
          }
          return;
        }
      }

      if (kIsWeb) {
        final extensionLogoutStarted =
            await WebLogoutFlow.openConnectLogoutPage();
        if (extensionLogoutStarted) {
          return;
        }
      }

      await _clearAuthSessionData();
      if (instant) {
        unawaited(_finishLogout(refreshToken, accessToken: accessToken));
        if (notify) {
          RefreshBus.instance.notify(reason: 'auth');
        }
        return;
      }
      await _finishLogout(refreshToken, accessToken: accessToken);
      if (notify) {
        RefreshBus.instance.notify(reason: 'auth');
      }
    } finally {
      _isLoggingOut = false;
    }
  }

  Future<void> _finishLogout(
    String? refreshToken, {
    String? accessToken,
  }) async {
    await _revokeServerSession(refreshToken, accessToken: accessToken);
    await _clearLocalCaches();
  }

  Future<void> _revokeServerSession(
    String? refreshToken, {
    String? accessToken,
  }) async {
    try {
      if (kIsWeb) {
        final uri = BracuLogout.mercureLogoutUri;
        await HttpUtils.client
            .delete(uri, headers: compressionHeadersForUri(uri))
            .timeout(_authRequestTimeout);
        return;
      }

      await _revokeMercureSession(accessToken);

      if (refreshToken != null && refreshToken.isNotEmpty) {
        final uri = Uri.parse(ApiConfig.logoutEndpoint);
        final body = HttpUtils.formBody(<String, String>{
          'client_id': ApiConfig.clientId,
          'refresh_token': refreshToken,
        });
        await HttpUtils.client
            .post(
              uri,
              headers: <String, String>{
                'Content-Type': 'application/x-www-form-urlencoded',
                ...compressionHeadersForUri(uri),
              },
              body: body,
            )
            .timeout(_authRequestTimeout);
      }
    } catch (error) {
      unawaited(AppLog.write('Server logout revocation failed: $error'));
    }
  }

  Future<void> _revokeMercureSession(String? accessToken) async {
    if (accessToken == null || accessToken.isEmpty) return;
    try {
      final uri = BracuLogout.mercureLogoutUri;
      await HttpUtils.client
          .delete(
            uri,
            headers: <String, String>{
              ...BracuLogout.mercureLogoutHeaders(accessToken: accessToken),
              ...compressionHeadersForUri(uri),
            },
          )
          .timeout(_authRequestTimeout);
    } catch (error) {
      unawaited(AppLog.write('Mercure logout revocation failed: $error'));
    }
  }

  Future<void> _loginMercureSession(String? accessToken) async {
    if (accessToken == null || accessToken.isEmpty) return;
    try {
      final uri = BracuLogout.mercureLoginUri;
      await HttpUtils.client
          .post(
            uri,
            headers: <String, String>{
              ...BracuLogout.mercureLoginHeaders(accessToken: accessToken),
              ...compressionHeadersForUri(uri),
            },
            body: '{}',
          )
          .timeout(_authRequestTimeout);
    } catch (error) {
      unawaited(AppLog.write('Mercure session login failed: $error'));
    }
  }

  Future<void> _clearAuthSessionData() async {
    await clearAuthenticationState(
      storage: _storage,
      clearTransientCaches: ApiClient().clearTransientCaches,
      clearUiArtifacts: AuthUiBridge.clearSessionArtifacts,
    );
  }

  Future<void> _clearLocalCaches() async {
    await AppStorage.instance.clear();
    await ProfileImageCache.instance.clear();
    CachedImage.clearMemoryCache();
    resetCachedCurrentSessionSemesterId();
    await LibSyncAuthService.instance.logout();
    try {
      final tempDir = await AppPaths.temporaryDirectory();
      if (await tempDir.exists()) {
        final entities = tempDir.listSync();
        for (final entity in entities) {
          try {
            entity.deleteSync(recursive: true);
          } catch (error) {
            unawaited(
              AppLog.write('Temporary logout file cleanup failed: $error'),
            );
          }
        }
      }
    } catch (error) {
      unawaited(AppLog.write('Temporary logout cleanup failed: $error'));
    }
  }

  Future<TokenRefreshStatus> refreshTokenStatus() async {
    if (_lastRefreshStatus != null && _lastRefreshTime != null) {
      final age = DateTime.now().difference(_lastRefreshTime!);
      if (age < _refreshResultTtl) {
        return _lastRefreshStatus!;
      }
    }

    final inFlight = _tokenRefreshInFlight;
    if (inFlight != null) {
      return inFlight;
    }

    final request = _performTokenRefresh();
    _tokenRefreshInFlight = request;
    try {
      return await request;
    } finally {
      if (identical(_tokenRefreshInFlight, request)) {
        _tokenRefreshInFlight = null;
      }
    }
  }

  Future<TokenRefreshStatus> _performTokenRefresh() async {
    try {
      final refreshToken = await _storage.read(
        key: PreConnectStorageKeys.refreshToken,
      );
      if (refreshToken == null || refreshToken.isEmpty) {
        _cacheRefreshResult(TokenRefreshStatus.invalidSession);
        return TokenRefreshStatus.invalidSession;
      }

      final status = await refreshBracuSessionTokens(
        refreshToken: refreshToken,
        timeout: _authRequestTimeout,
        persistTokens: (accessToken, refreshToken, idToken) async {
          await _storage.write(
            key: PreConnectStorageKeys.accessToken,
            value: accessToken,
          );
          await _storage.write(
            key: PreConnectStorageKeys.refreshToken,
            value: refreshToken,
          );
          if (idToken != null && idToken.isNotEmpty) {
            await _storage.write(
              key: PreConnectStorageKeys.idToken,
              value: idToken,
            );
          }
          ApiClient().clearTransientCaches();
          unawaited(_loginMercureSession(accessToken));
        },
        clearTokens: () async {
          await _storage.deleteAll();
          ApiClient().clearTransientCaches();
        },
      );
      _cacheRefreshResult(status);
      return status;
    } catch (e) {
      _cacheRefreshResult(TokenRefreshStatus.retryableFailure);
      return TokenRefreshStatus.retryableFailure;
    }
  }

  void _cacheRefreshResult(TokenRefreshStatus status) {
    _lastRefreshStatus = status;
    _lastRefreshTime = DateTime.now();
  }

  Future<bool> refreshToken() async {
    return (await refreshTokenStatus()) == TokenRefreshStatus.refreshed;
  }

  Future<bool> isLoggedIn() async {
    final token = await _storage.read(key: PreConnectStorageKeys.accessToken);
    return token != null && token.isNotEmpty;
  }

  Future<bool> ensureSignedIn() async {
    final accessToken = await _storage.read(
      key: PreConnectStorageKeys.accessToken,
    );
    if (accessToken == null || accessToken.isEmpty) {
      return false;
    }

    final expired = await isTokenExpired();
    if (!expired) {
      return true;
    }
    if (_bootstrapStartTime != null) {
      final timeSinceBootstrap = DateTime.now().difference(
        _bootstrapStartTime!,
      );
      if (timeSinceBootstrap < _bootstrapGracePeriod) {
        return true;
      }
    }
    if (!await ApiClient().hasConnection()) {
      return true;
    }
    final refreshStatus = await refreshTokenStatus();
    if (refreshStatus == TokenRefreshStatus.refreshed) {
      return true;
    }
    if (refreshStatus == TokenRefreshStatus.retryableFailure) {
      return true;
    }
    if (_bootstrapStartTime != null) {
      final timeSinceBootstrap = DateTime.now().difference(
        _bootstrapStartTime!,
      );
      if (timeSinceBootstrap < _bootstrapGracePeriod) {
        return false;
      }
    }
    await logout(force: true);
    return false;
  }

  bool _isValidJwt(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) {
        return false;
      }

      for (int i = 0; i < 3; i++) {
        if (parts[i].isEmpty) {
          return false;
        }
      }

      try {
        base64Url.decode(base64Url.normalize(parts[0]));
      } catch (e) {
        return false;
      }

      try {
        final payloadJson = utf8.decode(
          base64Url.decode(base64Url.normalize(parts[1])),
        );
        final payload = json.decode(payloadJson);
        if (payload is! Map || !payload.containsKey('exp')) {
          return false;
        }
      } catch (e) {
        return false;
      }

      try {
        base64Url.decode(base64Url.normalize(parts[2]));
      } catch (e) {
        return false;
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<DateTime> getTokenExpiryTime() async {
    final token = await _storage.read(key: PreConnectStorageKeys.accessToken);
    if (token == null || token.isEmpty) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
    if (!_isValidJwt(token)) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
    try {
      final parts = token.split('.');
      if (parts.length != 3) return DateTime.fromMillisecondsSinceEpoch(0);
      final payload = json.decode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      final exp = payload['exp'];
      if (exp == null) return DateTime.fromMillisecondsSinceEpoch(0);
      final seconds = int.tryParse('$exp');
      if (seconds == null) return DateTime.fromMillisecondsSinceEpoch(0);
      return DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
    } catch (e) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
  }

  Future<bool> isTokenExpired() async {
    final expiryTime = await getTokenExpiryTime();
    return DateTime.now().isAfter(expiryTime);
  }
}
