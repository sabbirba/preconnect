import 'package:flutter/foundation.dart'
    show ValueNotifier, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart' show TargetPlatform;
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:local_auth/local_auth.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:preconnect/tools/web_kv_store_stub.dart'
    if (dart.library.html) 'package:preconnect/tools/web_kv_store_web.dart';
import 'dart:io';

class TokenStorage {
  TokenStorage._();

  static final TokenStorage instance = TokenStorage._();
  static const String _cachedHasSessionKey = 'cached_has_auth_session';

  final FlutterSecureStorage _secure = const FlutterSecureStorage();

  bool get _useSecure =>
      !kIsWeb && defaultTargetPlatform != TargetPlatform.macOS;

  Future<String?> read({required String key}) async {
    if (kIsWeb) {
      final value = webKvGet(key);
      if (value != null && value.isNotEmpty) return value;
    }
    if (_useSecure) {
      return _secure.read(key: key);
    }
    final prefs = SharedPreferencesAsync();
    return prefs.getString(key);
  }

  Future<bool?> readCachedHasSession() async {
    final prefs = SharedPreferencesAsync();
    return await prefs.getBool(_cachedHasSessionKey);
  }

  Future<void> write({required String key, String? value}) async {
    if (kIsWeb && webKvSet(key, value)) {
      await _updateCachedSessionFlagForKey(key, value);
      return;
    }
    if (_useSecure) {
      await _secure.write(key: key, value: value);
      await _updateCachedSessionFlagForKey(key, value);
      return;
    }
    final prefs = SharedPreferencesAsync();
    if (value == null) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, value);
    }
    await _updateCachedSessionFlagForKey(key, value);
  }

  Future<void> deleteAll() async {
    if (kIsWeb) {
      webKvClearKeys(const ['access_token', 'refresh_token']);
      final prefs = SharedPreferencesAsync();
      await prefs.remove('access_token');
      await prefs.remove('refresh_token');
      await prefs.setBool(_cachedHasSessionKey, false);
      return;
    }
    if (_useSecure) {
      await _secure.deleteAll();
      final prefs = SharedPreferencesAsync();
      await prefs.setBool(_cachedHasSessionKey, false);
      return;
    }
    final prefs = SharedPreferencesAsync();
    await prefs.clear();
  }

  Future<void> _updateCachedSessionFlagForKey(String key, String? value) async {
    if (key != 'access_token') return;
    final prefs = SharedPreferencesAsync();
    final hasValue = value != null && value.isNotEmpty;
    await prefs.setBool(_cachedHasSessionKey, hasValue);
  }
}

const String kPreconnectUserAgent =
    'Mozilla/5.0 (Linux; Android 14; Mobile) '
    'AppleWebKit/537.36 (KHTML, like Gecko) '
    'Chrome/120.0.0.0 Mobile Safari/537.36 PreConnect';

class WebLoginSessionStore {
  WebLoginSessionStore._();

  static const String _studentEmailKey = 'web_login_student_email';
  static const String _webSessionIdKey = 'web_login_session_id';
  static const String _webSessionTokenKey = 'web_login_session_token';

  static Future<void> save({
    required String accessToken,
    required String refreshToken,
    required String studentEmail,
    String? webSessionId,
    String? webSessionToken,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await TokenStorage.instance.write(key: 'access_token', value: accessToken);
    await TokenStorage.instance.write(
      key: 'refresh_token',
      value: refreshToken,
    );
    await prefs.setString(_studentEmailKey, studentEmail.trim());
    final normalizedSessionId = (webSessionId ?? '').trim();
    final normalizedSessionToken = (webSessionToken ?? '').trim();
    if (normalizedSessionId.isNotEmpty && normalizedSessionToken.isNotEmpty) {
      await prefs.setString(_webSessionIdKey, normalizedSessionId);
      await prefs.setString(_webSessionTokenKey, normalizedSessionToken);
    }
  }

  static Future<bool> hasValidSession() async {
    final sessionId = await getWebSessionId();
    final sessionToken = await getWebSessionToken();
    return (sessionId ?? '').isNotEmpty && (sessionToken ?? '').isNotEmpty;
  }

  static Future<String?> getWebSessionId() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_webSessionIdKey)?.trim();
    if (value == null || value.isEmpty) return null;
    return value;
  }

  static Future<String?> getWebSessionToken() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_webSessionTokenKey)?.trim();
    if (value == null || value.isEmpty) return null;
    return value;
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_studentEmailKey);
    await prefs.remove(_webSessionIdKey);
    await prefs.remove(_webSessionTokenKey);
  }
}

class CaptiveLoginCredentials {
  const CaptiveLoginCredentials({required this.password});

  final String password;
}

class CaptiveLoginStore {
  CaptiveLoginStore._();

  static final CaptiveLoginStore instance = CaptiveLoginStore._();
  static const String _passwordKey = 'wifi_captive_password';
  static const String _autoExtendEnabledKey = 'wifi_captive_auto_extend';
  static const String defaultCampusSsid = 'Student-WiFi';

  final TokenStorage _storage = TokenStorage.instance;

  Future<bool> readAutoExtendEnabled() async {
    final raw = (await _storage.read(key: _autoExtendEnabledKey) ?? 'true')
        .trim()
        .toLowerCase();
    return raw != 'false';
  }

  Future<CaptiveLoginCredentials?> read() async {
    final password = await _storage.read(key: _passwordKey) ?? '';
    if (password.isEmpty) return null;
    return CaptiveLoginCredentials(password: password);
  }

  Future<void> save({required String password}) async {
    await _storage.write(key: _passwordKey, value: password);
  }

  Future<void> saveAutoExtendEnabled(bool enabled) async {
    await _storage.write(
      key: _autoExtendEnabledKey,
      value: enabled ? 'true' : 'false',
    );
  }

  Future<void> clear() async {
    await _storage.write(key: _passwordKey, value: null);
    await _storage.write(key: _autoExtendEnabledKey, value: null);
  }
}

class CoursePinStore {
  static String _key(String scope) => 'course_pins_$scope';

  static Future<Set<String>> load(String scope) async {
    final prefs = await SharedPreferences.getInstance();
    final values = prefs.getStringList(_key(scope)) ?? const <String>[];
    return values
        .map((e) => e.trim().toUpperCase())
        .where((e) => e.isNotEmpty)
        .toSet();
  }

  static Future<void> save(String scope, Set<String> pins) async {
    final prefs = await SharedPreferences.getInstance();
    final values =
        pins
            .map((e) => e.trim().toUpperCase())
            .where((e) => e.isNotEmpty)
            .toList()
          ..sort();
    await prefs.setStringList(_key(scope), values);
  }
}

class HomeCardPreferences {
  HomeCardPreferences._();

  static const String _showQuickAccessSectionKey =
      'home_show_quick_access_section';
  static const String _showRamadanCardKey = 'home_show_ramadan_card';
  static const String _showExamCountdownCardKey =
      'home_show_exam_countdown_card';
  static const String _showTodayScheduleKey = 'home_show_today_schedule';

  static const HomeCardVisibility defaults = HomeCardVisibility(
    showQuickAccessSection: true,
    showRamadanCard: true,
    showExamCountdownCard: true,
    showTodaySchedule: true,
  );

  static Future<HomeCardVisibility> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return HomeCardVisibility(
        showQuickAccessSection:
            prefs.getBool(_showQuickAccessSectionKey) ?? true,
        showRamadanCard: prefs.getBool(_showRamadanCardKey) ?? true,
        showExamCountdownCard: prefs.getBool(_showExamCountdownCardKey) ?? true,
        showTodaySchedule: prefs.getBool(_showTodayScheduleKey) ?? true,
      );
    } catch (_) {
      return defaults;
    }
  }

  static Future<void> setShowRamadanCard(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_showRamadanCardKey, value);
    } catch (_) {}
  }

  static Future<void> setShowExamCountdownCard(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_showExamCountdownCardKey, value);
    } catch (_) {}
  }

  static Future<void> setShowQuickAccessSection(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_showQuickAccessSectionKey, value);
    } catch (_) {}
  }

  static Future<void> setShowTodaySchedule(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_showTodayScheduleKey, value);
    } catch (_) {}
  }
}

class AdsPreferences {
  AdsPreferences._();

  static final AdsPreferences instance = AdsPreferences._();

  static const String _hideAdsKey = 'hide_ads';

  final ValueNotifier<bool> adsVisible = ValueNotifier<bool>(true);
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      adsVisible.value = !(prefs.getBool(_hideAdsKey) ?? false);
    } catch (_) {
      adsVisible.value = true;
    }
  }

  bool get isVisible => adsVisible.value;

  bool get isHidden => !adsVisible.value;

  Future<void> setHidden(bool hidden) async {
    try {
      await load();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_hideAdsKey, hidden);
      adsVisible.value = !hidden;
    } catch (_) {}
  }
}

class HomeCardVisibility {
  const HomeCardVisibility({
    required this.showQuickAccessSection,
    required this.showRamadanCard,
    required this.showExamCountdownCard,
    required this.showTodaySchedule,
  });

  final bool showQuickAccessSection;
  final bool showRamadanCard;
  final bool showExamCountdownCard;
  final bool showTodaySchedule;
}

class InAppReviewPrompt {
  InAppReviewPrompt._();
  static const String _launchCountKey = 'review_launch_count';
  static const String _firstOpenKey = 'review_first_open_utc';
  static const String _lastAttemptKey = 'review_last_attempt_utc';
  static const String _lastPromptKey = 'review_last_prompt_utc';

  static const int _minLaunchCount = 2;
  static const int _minDaysFromFirstOpen = 0;
  static const int _cooldownDays = 14;
  static const int _minHoursBetweenAttempts = 24;

  static Future<void> maybePrompt() async {
    try {
      if (!(Platform.isAndroid || Platform.isIOS)) return;

      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now().toUtc();

      final launches = (prefs.getInt(_launchCountKey) ?? 0) + 1;
      await prefs.setInt(_launchCountKey, launches);

      final firstOpenMs =
          prefs.getInt(_firstOpenKey) ?? now.millisecondsSinceEpoch;
      if (!prefs.containsKey(_firstOpenKey)) {
        await prefs.setInt(_firstOpenKey, firstOpenMs);
      }
      final firstOpen = DateTime.fromMillisecondsSinceEpoch(
        firstOpenMs,
        isUtc: true,
      );

      final lastPromptMs = prefs.getInt(_lastPromptKey);
      final lastAttemptMs = prefs.getInt(_lastAttemptKey);

      if (launches < _minLaunchCount) return;
      if (now.difference(firstOpen).inDays < _minDaysFromFirstOpen) return;
      if (lastAttemptMs != null) {
        final lastAttempt = DateTime.fromMillisecondsSinceEpoch(
          lastAttemptMs,
          isUtc: true,
        );
        if (now.difference(lastAttempt).inHours < _minHoursBetweenAttempts) {
          return;
        }
      }
      if (lastPromptMs != null) {
        final lastPrompt = DateTime.fromMillisecondsSinceEpoch(
          lastPromptMs,
          isUtc: true,
        );
        if (now.difference(lastPrompt).inDays < _cooldownDays) return;
      }
      await prefs.setInt(_lastAttemptKey, now.millisecondsSinceEpoch);

      final inAppReview = InAppReview.instance;
      final available = await inAppReview.isAvailable();
      if (!available) return;
      await inAppReview.requestReview();
      await prefs.setInt(_lastPromptKey, now.millisecondsSinceEpoch);
    } catch (_) {}
  }

  static Future<bool> openStoreListing({String? iosAppStoreId}) async {
    try {
      final inAppReview = InAppReview.instance;
      if (Platform.isIOS) {
        final appStoreId = (iosAppStoreId ?? '').trim();
        if (appStoreId.isEmpty) return false;
        await inAppReview.openStoreListing(appStoreId: appStoreId);
        return true;
      }
      await inAppReview.openStoreListing();
      return true;
    } catch (_) {
      return false;
    }
  }
}

class PlatformPermissions {
  const PlatformPermissions._();

  static Future<bool> requestScannerCameraPermission() async {
    if (kIsWeb) return true;
    if (defaultTargetPlatform == TargetPlatform.macOS) return true;

    final status = await Permission.camera.status;
    final requested = status.isGranted
        ? status
        : await Permission.camera.request();
    return requested.isGranted;
  }

  static Future<bool> requestGalleryImagePermission() async {
    if (kIsWeb) return true;
    if (defaultTargetPlatform == TargetPlatform.macOS) return true;

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final photos = await Permission.photos.request();
      return photos.isGranted || photos.isLimited;
    }

    if (defaultTargetPlatform == TargetPlatform.android) {
      final photos = await Permission.photos.request();
      if (photos.isGranted) return true;
      final storage = await Permission.storage.request();
      return storage.isGranted;
    }

    return true;
  }
}

class AppLockService {
  static const String _prefsKey = 'app_lock_enabled';
  final LocalAuthentication _auth = LocalAuthentication();

  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefsKey) ?? false;
  }

  Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, value);
  }

  Future<bool> authenticate({required String reason}) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        biometricOnly: false,
        sensitiveTransaction: true,
        persistAcrossBackgrounding: true,
      );
    } catch (_) {
      return false;
    }
  }
}

class ProfileImageCache {
  ProfileImageCache._();
  static final instance = ProfileImageCache._();

  static const _cachedUrlKey = 'profile_image_cached_url';
  static const _legacyCachedBytesKey = 'profile_image_cached_bytes';

  File? _cachedFile;

  Future<File?> getProfileImage(String? photoUrl) async {
    if (photoUrl == null || photoUrl.isEmpty) return null;

    if (_cachedFile != null && _cachedFile!.existsSync()) {
      return _cachedFile;
    }

    final dir = await getApplicationSupportDirectory();
    final file = File('${dir.path}/profile_photo.jpg');
    final prefs = await SharedPreferences.getInstance();

    final cachedUrl = prefs.getString(_cachedUrlKey);
    await prefs.remove(_legacyCachedBytesKey);

    if (file.existsSync() &&
        file.lengthSync() > 0 &&
        (cachedUrl == null || cachedUrl == photoUrl)) {
      _cachedFile = file;
      _downloadInBackground(photoUrl, file);
      return file;
    }

    try {
      final response = await http.get(Uri.parse(photoUrl));
      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        await file.writeAsBytes(response.bodyBytes, flush: true);
        await prefs.setString(_cachedUrlKey, photoUrl);
        _cachedFile = file;
        return file;
      }
    } catch (_) {}

    return null;
  }

  void _downloadInBackground(String url, File file) async {
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        await file.writeAsBytes(response.bodyBytes, flush: true);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_cachedUrlKey, url);
      }
    } catch (_) {}
  }

  void invalidate() {
    _cachedFile = null;
  }

  Future<void> clear() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/profile_photo.jpg');
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cachedUrlKey);
    await prefs.remove(_legacyCachedBytesKey);
    _cachedFile = null;
  }
}
