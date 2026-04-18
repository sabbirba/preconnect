import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:synchronized/synchronized.dart';
import 'package:preconnect/tools/app_storage.dart';
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/api/api_client.dart';
import 'package:preconnect/api/friend_schedule_store.dart';
import 'package:preconnect/api/seat_status_service.dart';
import 'package:preconnect/pages/login.dart';
import 'package:preconnect/tools/cached_image.dart';
import 'package:preconnect/tools/push_notifications_service.dart';
import 'package:preconnect/tools/token_storage.dart';

enum TokenRefreshStatus { refreshed, invalidSession, retryableFailure }

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal() {
    // Start grace period immediately on app startup
    _bootstrapStartTime = DateTime.now();
  }

  final TokenStorage _storage = TokenStorage.instance;
  static const Duration _authRequestTimeout = Duration(seconds: 12);

  // Mutex lock to prevent concurrent token refresh race conditions
  static final _tokenRefreshLock = Lock();

  // Cache token refresh result to avoid repeated refreshes within 5 seconds
  static TokenRefreshStatus? _lastRefreshStatus;
  static DateTime? _lastRefreshTime;
  static const Duration _refreshResultTtl = Duration(seconds: 5);

  // Grace period to prevent logout during initial bootstrap (tokens just written)
  static DateTime? _bootstrapStartTime;
  static const Duration _bootstrapGracePeriod = Duration(seconds: 10);

  // Flag to prevent concurrent logout race conditions
  static bool _isLoggingOut = false;

  Future<void> login(BuildContext context) async {
    Navigator.pushNamed(context, '/login');
  }

  Future<void> logout({bool instant = false, bool force = false}) async {
    // Prevent concurrent logout operations
    if (_isLoggingOut) {
      debugPrint(
        '[AUTH] logout() already in progress - ignoring concurrent logout call',
      );
      return;
    }
    _isLoggingOut = true;

    try {
      debugPrint(
        '[AUTH] logout() called - starting logout sequence (force=$force)',
      );

      // CRITICAL: Prevent accidental token clearing during bootstrap
      if (!force && _bootstrapStartTime != null) {
        final timeSinceBootstrap = DateTime.now().difference(
          _bootstrapStartTime!,
        );
        if (timeSinceBootstrap < _bootstrapGracePeriod) {
          debugPrint(
            '[AUTH] ⚠ BLOCKED logout during bootstrap grace period (${timeSinceBootstrap.inMilliseconds}ms since startup)',
          );
          debugPrint(
            '[AUTH] Tokens are likely fresh from login - refusing to clear them',
          );
          debugPrint(
            '[AUTH] Call logout(force: true) if logout is truly needed',
          );
          return;
        }
      }

      // Verify tokens actually exist before clearing them
      final refreshToken = await _storage.read(key: 'refresh_token');
      final accessToken = await _storage.read(key: 'access_token');
      if (accessToken == null && refreshToken == null) {
        debugPrint(
          '[AUTH] logout() called but no tokens present - skipping logout',
        );
        return;
      }

      await _clearAuthSessionData();
      if (instant) {
        debugPrint(
          '[AUTH] logout() instant=true, finishing logout in background',
        );
        unawaited(_finishLogout(refreshToken));
        return;
      }
      debugPrint('[AUTH] logout() awaiting full logout completion');
      await _finishLogout(refreshToken);
    } finally {
      _isLoggingOut = false;
      debugPrint(
        '[AUTH] logout() completed, concurrent logout protection released',
      );
    }
  }

  Future<void> _finishLogout(String? refreshToken) async {
    debugPrint('[AUTH] _finishLogout() starting - revoking server session');
    await _revokeServerSession(refreshToken);
    debugPrint('[AUTH] _finishLogout() - clearing local caches');
    await _clearLocalCaches();
    debugPrint('[AUTH] _finishLogout() completed');
  }

  Future<void> _revokeServerSession(String? refreshToken) async {
    try {
      if (!kIsWeb && refreshToken != null && refreshToken.isNotEmpty) {
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
    debugPrint(
      '[AUTH] _clearAuthSessionData() - deleting all tokens from storage',
    );
    await _storage.deleteAll();
    debugPrint('[AUTH] _clearAuthSessionData() - clearing web login session');
    await WebLoginSessionStore.clear();
    debugPrint(
      '[AUTH] _clearAuthSessionData() - clearing login page artifacts',
    );
    await LoginPage.clearSessionArtifacts();
    debugPrint('[AUTH] _clearAuthSessionData() completed');
  }

  Future<void> _clearLocalCaches() async {
    debugPrint(
      '[AUTH] _clearLocalCaches() starting - clearing app caches (NOT tokens)...',
    );
    try {
      await SeatAlertSyncService().clearAll();
      debugPrint('[AUTH] _clearLocalCaches() - SeatAlertSyncService cleared');
    } catch (e) {
      debugPrint(
        '[AUTH] _clearLocalCaches() ERROR clearing SeatAlertSyncService: $e',
      );
    }

    // CRITICAL: Only clear specific cache keys, NOT all of AppStorage (which contains tokens!)
    // AppStorage.clear() was wiping tokens and causing all API failures
    final cacheKeysToRemove = [
      'StudentSchedule',
      'StudentProgramProgress',
      'StudentProgramProgressSummary',
      'SemesterPaymentInfo',
      'profile_data_cache',
      'advising_data_cache',
      'attendance_data_cache',
      'scraper_transport_v1',
      'scraper_campus_map_v1',
      'schedule_planner_items_v1',
      'seat_alert_configs_v1',
      'home_show_quick_access_section',
      'home_show_ramadan_card',
      'home_show_exam_countdown_card',
      'home_show_today_schedule',
      'home_show_sponsored_content',
    ];
    for (final key in cacheKeysToRemove) {
      try {
        await AppStorage.instance.remove(key);
      } catch (_) {}
    }
    debugPrint(
      '[AUTH] _clearLocalCaches() - AppStorage cache keys cleared (tokens preserved)',
    );

    await FriendScheduleStore().clearAll();
    debugPrint('[AUTH] _clearLocalCaches() - FriendScheduleStore cleared');
    await SeatStatusService().clearAll();
    debugPrint('[AUTH] _clearLocalCaches() - SeatStatusService cleared');
    await ProfileImageCache.instance.clear();
    debugPrint('[AUTH] _clearLocalCaches() - ProfileImageCache cleared');
    CachedImage.clearMemoryCache();
    debugPrint('[AUTH] _clearLocalCaches() - CachedImage memory cleared');
    debugPrint(
      '[AUTH] _clearLocalCaches() completed - app caches cleared, tokens preserved',
    );
  }

  Future<TokenRefreshStatus> refreshTokenStatus() async {
    // Serialize token refresh operations with a lock
    return _tokenRefreshLock.synchronized(() async {
      // Check if another thread just completed refresh within TTL
      if (_lastRefreshStatus != null && _lastRefreshTime != null) {
        final age = DateTime.now().difference(_lastRefreshTime!);
        if (age < _refreshResultTtl) {
          debugPrint(
            '[AUTH] Returning cached refresh result from ${age.inMilliseconds}ms ago',
          );
          return _lastRefreshStatus!;
        }
      }

      // Perform actual token refresh
      return _performTokenRefresh();
    });
  }

  Future<TokenRefreshStatus> _performTokenRefresh() async {
    try {
      final refreshToken = await _storage.read(key: 'refresh_token');
      if (refreshToken == null || refreshToken.isEmpty) {
        _cacheRefreshResult(TokenRefreshStatus.invalidSession);
        return TokenRefreshStatus.invalidSession;
      }

      final response = await http
          .post(
            Uri.parse(ApiConfig.tokenEndpoint),
            headers: {'Content-Type': 'application/x-www-form-urlencoded'},
            body: {
              'grant_type': 'refresh_token',
              'refresh_token': refreshToken,
              'client_id': ApiConfig.clientId,
            },
          )
          .timeout(_authRequestTimeout);

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final accessToken = data['access_token'] as String?;
        final newRefreshToken = data['refresh_token'] as String?;
        if (accessToken == null ||
            accessToken.isEmpty ||
            newRefreshToken == null ||
            newRefreshToken.isEmpty) {
          _cacheRefreshResult(TokenRefreshStatus.invalidSession);
          return TokenRefreshStatus.invalidSession;
        }
        await _storage.write(key: 'access_token', value: accessToken);
        await _storage.write(key: 'refresh_token', value: newRefreshToken);
        _cacheRefreshResult(TokenRefreshStatus.refreshed);
        return TokenRefreshStatus.refreshed;
      }

      if (response.statusCode == 400 || response.statusCode == 401) {
        _cacheRefreshResult(TokenRefreshStatus.invalidSession);
        return TokenRefreshStatus.invalidSession;
      }

      _cacheRefreshResult(TokenRefreshStatus.retryableFailure);
      return TokenRefreshStatus.retryableFailure;
    } catch (e) {
      debugPrint('[AUTH] Token refresh error: $e');
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
    final token = await _storage.read(key: 'access_token');
    return token != null && token.isNotEmpty;
  }

  Future<bool> ensureSignedIn() async {
    debugPrint('[AUTH] ensureSignedIn: Checking if user is still signed in...');
    final accessToken = await _storage.read(key: 'access_token');
    if (accessToken == null || accessToken.isEmpty) {
      debugPrint('[AUTH] ensureSignedIn: No access_token found');
      return false;
    }
    debugPrint(
      '[AUTH] ensureSignedIn: Found access_token (${accessToken.length} bytes), checking expiry...',
    );

    final expired = await isTokenExpired();
    debugPrint('[AUTH] ensureSignedIn: Token expired=$expired');
    if (!expired) {
      debugPrint(
        '[AUTH] ensureSignedIn: Token is still valid, user is signed in',
      );
      return true;
    }

    debugPrint(
      '[AUTH] ensureSignedIn: Token is expired, checking if in bootstrap grace period...',
    );
    if (_bootstrapStartTime != null) {
      final timeSinceBootstrap = DateTime.now().difference(
        _bootstrapStartTime!,
      );
      if (timeSinceBootstrap < _bootstrapGracePeriod) {
        debugPrint(
          '[AUTH] ensureSignedIn: In bootstrap grace period (${timeSinceBootstrap.inMilliseconds}ms), treating expired token as valid',
        );
        return true;
      }
    }

    debugPrint(
      '[AUTH] ensureSignedIn: Token is expired, checking network connection...',
    );
    if (!await ApiClient().hasConnection()) {
      debugPrint(
        '[AUTH] ensureSignedIn: No network connection, returning true to avoid logout',
      );
      return true;
    }

    debugPrint(
      '[AUTH] ensureSignedIn: Token expired and network available, attempting refresh...',
    );
    final refreshStatus = await refreshTokenStatus();
    debugPrint('[AUTH] ensureSignedIn: Refresh status=$refreshStatus');
    if (refreshStatus == TokenRefreshStatus.refreshed) {
      debugPrint('[AUTH] ensureSignedIn: Token refreshed successfully');
      return true;
    }
    if (refreshStatus == TokenRefreshStatus.retryableFailure) {
      debugPrint(
        '[AUTH] ensureSignedIn: Refresh failed but retryable, returning true to allow retry',
      );
      return true;
    }

    debugPrint(
      '[AUTH] ensureSignedIn: CRITICAL - Token refresh failed non-recoverable',
    );
    debugPrint(
      '[AUTH] ensureSignedIn: Checking if in bootstrap grace period before logout...',
    );
    if (_bootstrapStartTime != null) {
      final timeSinceBootstrap = DateTime.now().difference(
        _bootstrapStartTime!,
      );
      if (timeSinceBootstrap < _bootstrapGracePeriod) {
        debugPrint(
          '[AUTH] ensureSignedIn: In bootstrap grace period (${timeSinceBootstrap.inMilliseconds}ms), returning false without logout',
        );
        return false;
      }
    }
    await logout();
    return false;
  }

  /// Validates JWT token format and structure
  /// Returns true if token has valid 3-part structure, valid base64 encoding, and exp claim
  bool _isValidJwt(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) {
        debugPrint('[AUTH] JWT validation failed: not 3-part structure');
        return false;
      }

      for (int i = 0; i < 3; i++) {
        if (parts[i].isEmpty) {
          debugPrint('[AUTH] JWT validation failed: empty part at index $i');
          return false;
        }
      }

      // Verify header is valid base64url
      try {
        base64Url.decode(base64Url.normalize(parts[0]));
      } catch (e) {
        debugPrint('[AUTH] JWT validation failed: invalid header base64: $e');
        return false;
      }

      // Verify payload is valid base64url and contains exp claim
      try {
        final payloadJson = utf8.decode(
          base64Url.decode(base64Url.normalize(parts[1])),
        );
        final payload = json.decode(payloadJson);
        if (payload is! Map || !payload.containsKey('exp')) {
          debugPrint('[AUTH] JWT validation failed: missing exp claim');
          return false;
        }
      } catch (e) {
        debugPrint(
          '[AUTH] JWT validation failed: invalid payload base64 or JSON: $e',
        );
        return false;
      }

      // Verify signature is valid base64url (doesn't need to be valid signature, just format)
      try {
        base64Url.decode(base64Url.normalize(parts[2]));
      } catch (e) {
        debugPrint(
          '[AUTH] JWT validation failed: invalid signature base64: $e',
        );
        return false;
      }

      debugPrint('[AUTH] JWT validation passed');
      return true;
    } catch (e) {
      debugPrint('[AUTH] JWT validation error: $e');
      return false;
    }
  }

  Future<DateTime> getTokenExpiryTime() async {
    final token = await _storage.read(key: 'access_token');
    if (token == null || token.isEmpty) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
    if (!_isValidJwt(token)) {
      debugPrint('[AUTH] Rejecting invalid JWT token');
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
      return DateTime.fromMillisecondsSinceEpoch(exp * 1000);
    } catch (e) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
  }

  Future<bool> isTokenExpired() async {
    final expiryTime = await getTokenExpiryTime();
    return DateTime.now().isAfter(expiryTime);
  }
}
