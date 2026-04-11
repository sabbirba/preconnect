import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/api/api_client.dart';
import 'package:preconnect/api/friend_schedule_store.dart';
import 'package:preconnect/api/sembast_cache.dart';
import 'package:preconnect/api/seat_status_service.dart';
import 'package:preconnect/pages/login.dart';
import 'package:preconnect/tools/cached_image.dart';
import 'package:preconnect/tools/push_notifications_service.dart';
import 'package:preconnect/tools/token_storage.dart';

enum TokenRefreshStatus { refreshed, invalidSession, retryableFailure }

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  final TokenStorage _storage = TokenStorage.instance;
  static const Duration _authRequestTimeout = Duration(seconds: 12);

  Future<void> login(BuildContext context) async {
    Navigator.pushNamed(context, '/login');
  }

  Future<void> logout({bool instant = false}) async {
    final refreshToken = await _storage.read(key: 'refresh_token');
    await _clearAuthSessionData();
    if (instant) {
      unawaited(_finishLogout(refreshToken));
      return;
    }
    await _finishLogout(refreshToken);
  }

  Future<void> _finishLogout(String? refreshToken) async {
    await _revokeServerSession(refreshToken);
    await _clearLocalCaches();
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
    await _storage.deleteAll();
    await WebLoginSessionStore.clear();
    await LoginPage.clearSessionArtifacts();
  }

  Future<void> _clearLocalCaches() async {
    try {
      await SeatAlertSyncService().clearAll();
    } catch (_) {}
    final asyncPrefs = SharedPreferencesAsync();
    await asyncPrefs.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    await SembastCache().clearAll();
    await FriendScheduleStore().clearAll();
    await SeatStatusService().clearAll();
    await ProfileImageCache.instance.clear();
    CachedImage.clearMemoryCache();
  }

  Future<TokenRefreshStatus> refreshTokenStatus() async {
    try {
      final refreshToken = await _storage.read(key: 'refresh_token');
      if (refreshToken == null || refreshToken.isEmpty) {
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
          return TokenRefreshStatus.invalidSession;
        }
        await _storage.write(key: 'access_token', value: accessToken);
        await _storage.write(key: 'refresh_token', value: newRefreshToken);
        return TokenRefreshStatus.refreshed;
      }

      if (response.statusCode == 400 || response.statusCode == 401) {
        return TokenRefreshStatus.invalidSession;
      }

      return TokenRefreshStatus.retryableFailure;
    } catch (_) {
      return TokenRefreshStatus.retryableFailure;
    }
  }

  Future<bool> refreshToken() async {
    return (await refreshTokenStatus()) == TokenRefreshStatus.refreshed;
  }

  Future<bool> isLoggedIn() async {
    final token = await _storage.read(key: 'access_token');
    return token != null && token.isNotEmpty;
  }

  Future<bool> ensureSignedIn() async {
    final accessToken = await _storage.read(key: 'access_token');
    if (accessToken == null || accessToken.isEmpty) return false;

    final expired = await isTokenExpired();
    if (!expired) return true;

    if (!await ApiClient().hasConnection()) return true;

    final refreshStatus = await refreshTokenStatus();
    if (refreshStatus == TokenRefreshStatus.refreshed) return true;
    if (refreshStatus == TokenRefreshStatus.retryableFailure) return true;

    await logout();
    return false;
  }

  Future<DateTime> getTokenExpiryTime() async {
    final token = await _storage.read(key: 'access_token');
    if (token == null || token.isEmpty) {
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
