import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:preconnect/api/app_preferences_store.dart';
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/api/api_client.dart';
import 'package:preconnect/api/friend_schedule_store.dart';
import 'package:preconnect/api/custom_schedules_service.dart';
import 'package:preconnect/api/profile_service.dart';
import 'package:preconnect/pages/login.dart';
import 'package:preconnect/tools/cached_image.dart';
import 'package:preconnect/tools/preconnect_constants.dart';
import 'package:preconnect/tools/token_refresh_flow.dart';
import 'package:preconnect/tools/web_shared.dart';
import 'package:preconnect/tools/token_storage.dart';

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

  Future<void> login(BuildContext context) async {
    Navigator.pushNamed(context, '/login');
  }

  Future<void> logout({bool instant = false, bool force = false}) async {
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

      final refreshToken = await _storage.read(
        key: PreconnectStorageKeys.refreshToken,
      );
      final accessToken = await _storage.read(
        key: PreconnectStorageKeys.accessToken,
      );
      if (accessToken == null && refreshToken == null) {
        return;
      }

      if (kIsWeb) {
        unawaited(WebLogoutFlow.openConnectLogoutPage());
      }

      await _clearAuthSessionData();
      if (instant) {
        unawaited(_finishLogout(refreshToken, accessToken: accessToken));
        return;
      }
      await _finishLogout(refreshToken, accessToken: accessToken);
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
        await http
            .delete(
              Uri.parse(
                '${ApiConfig.connectWebApiBase}${ApiConfig.connectMercureLogoutPath}',
              ),
            )
            .timeout(_authRequestTimeout);
        return;
      }

      if (refreshToken != null && refreshToken.isNotEmpty) {
        await http
            .post(
              Uri.parse(ApiConfig.logoutEndpoint),
              headers: {'Content-Type': 'application/x-www-form-urlencoded'},
              body: {
                'client_id': ApiConfig.clientId,
                'refresh_token': refreshToken,
              },
            )
            .timeout(_authRequestTimeout);
      }
    } catch (_) {}
  }

  Future<void> _clearAuthSessionData() async {
    await _storage.deleteAll();
    await LoginPage.clearSessionArtifacts();
  }

  Future<void> _clearLocalCaches() async {
    final keepKeys = <String>{
      PreconnectStorageKeys.accessToken,
      PreconnectStorageKeys.refreshToken,
      PreconnectStorageKeys.cachedHasAuthSession,
      CustomSchedulesService.cacheKey,
    };
    keepKeys.addAll(ProfileService.profileFields);

    await AppPreferencesStore().clearAllExcept(keepKeys);

    await FriendScheduleStore().clearAll();
    await ProfileImageCache.instance.clear();
    CachedImage.clearMemoryCache();
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
        key: PreconnectStorageKeys.refreshToken,
      );
      if (refreshToken == null || refreshToken.isEmpty) {
        _cacheRefreshResult(TokenRefreshStatus.invalidSession);
        return TokenRefreshStatus.invalidSession;
      }

      final status = await refreshBracuSessionTokens(
        refreshToken: refreshToken,
        timeout: _authRequestTimeout,
        persistTokens: (accessToken, refreshToken) async {
          await _storage.write(
            key: PreconnectStorageKeys.accessToken,
            value: accessToken,
          );
          await _storage.write(
            key: PreconnectStorageKeys.refreshToken,
            value: refreshToken,
          );
        },
        clearTokens: () async {
          await _storage.deleteAll();
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
    final token = await _storage.read(key: PreconnectStorageKeys.accessToken);
    return token != null && token.isNotEmpty;
  }

  Future<bool> ensureSignedIn() async {
    final accessToken = await _storage.read(
      key: PreconnectStorageKeys.accessToken,
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
    final token = await _storage.read(key: PreconnectStorageKeys.accessToken);
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
