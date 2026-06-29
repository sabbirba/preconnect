import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart'
    show ValueNotifier, defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:preconnect/tools/http/http_utils.dart';

import 'package:in_app_review/in_app_review.dart';
import 'package:local_auth/local_auth.dart';
import 'package:preconnect/api/api_client.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:preconnect/tools/app_storage.dart';
import 'package:preconnect/tools/app_paths.dart';
import 'package:preconnect/tools/preconnect_constants.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:preconnect/tools/platform_stub.dart'
    if (dart.library.html) 'package:preconnect/tools/storage_web.dart';

class TokenPersistenceException implements Exception {
  TokenPersistenceException(this.message);
  final String message;

  @override
  String toString() => 'TokenPersistenceException: $message';
}

class TokenStorage {
  TokenStorage._();

  static final TokenStorage instance = TokenStorage._();
  static const String _cachedHasSessionKey =
      PreConnectStorageKeys.cachedHasAuthSession;

  static const Set<String> _sensitiveKeys = {
    PreConnectStorageKeys.accessToken,
    PreConnectStorageKeys.refreshToken,
    'wifi_captive_password',
  };

  static const _secureStorage = FlutterSecureStorage();

  Future<String?> read({required String key}) async {
    if (kIsWeb) {
      return await webExtensionStorageGet(key);
    }

    if (_sensitiveKeys.contains(key)) {
      try {
        final val = await _secureStorage.read(key: key);
        if (val != null) return val;
      } catch (_) {}
      return await AppStorage.instance.getString(key);
    }

    final value = await AppStorage.instance.getString(key);
    if (value == null || value.isEmpty) return null;
    return value;
  }

  Future<bool> hasAccessToken() async {
    final value = await read(key: PreConnectStorageKeys.accessToken);
    return value != null && value.isNotEmpty;
  }

  Future<bool?> readCachedHasSession() {
    if (kIsWeb) {
      return webExtensionStorageGet(_cachedHasSessionKey).then((value) {
        final raw = value?.trim().toLowerCase();
        if (raw == null || raw.isEmpty) return null;
        return raw == 'true';
      });
    }
    return AppStorage.instance.getBool(_cachedHasSessionKey);
  }

  Future<void> write({required String key, String? value}) async {
    if (kIsWeb) {
      await webExtensionStorageSet(key, value);
      await _updateCachedSessionFlagForKey(key, value);
      return;
    }

    if (_sensitiveKeys.contains(key)) {
      try {
        if (value == null || value.isEmpty) {
          await _secureStorage.delete(key: key);
        } else {
          await _secureStorage.write(key: key, value: value);
        }
        await AppStorage.instance.remove(key);
      } catch (_) {
        if (value == null || value.isEmpty) {
          await AppStorage.instance.remove(key);
        } else {
          await AppStorage.instance.setString(key, value);
        }
      }
    } else {
      if (value == null || value.isEmpty) {
        await AppStorage.instance.remove(key);
      } else {
        await AppStorage.instance.setString(key, value);
      }
    }

    await _updateCachedSessionFlagForKey(key, value);
  }

  Future<void> deleteAll() async {
    try {
      await _secureStorage.delete(key: PreConnectStorageKeys.accessToken);
      await _secureStorage.delete(key: PreConnectStorageKeys.refreshToken);
      await _secureStorage.delete(key: 'wifi_captive_password');
    } catch (_) {}
    await AppStorage.instance.remove(PreConnectStorageKeys.accessToken);
    await AppStorage.instance.remove(PreConnectStorageKeys.refreshToken);
    await AppStorage.instance.remove(PreConnectStorageKeys.idToken);
    await AppStorage.instance.setBool(_cachedHasSessionKey, false);
    ApiClient().clearTransientCaches();

    if (kIsWeb) {
      await webExtensionStorageRemoveKeys(const [
        PreConnectStorageKeys.accessToken,
        PreConnectStorageKeys.refreshToken,
        PreConnectStorageKeys.idToken,
        _cachedHasSessionKey,
      ]);
    }
  }

  Future<void> _updateCachedSessionFlagForKey(String key, String? value) async {
    if (key != PreConnectStorageKeys.accessToken) return;
    final hasValue = value != null && value.isNotEmpty;
    await AppStorage.instance.setBool(_cachedHasSessionKey, hasValue);
  }
}

const String kPreConnectUserAgent =
    'Mozilla/5.0 (Linux; Android 14; Mobile) '
    'AppleWebKit/537.36 (KHTML, like Gecko) '
    'Chrome/120.0.0.0 Mobile Safari/537.36 PreConnect';

class CaptiveLoginCredentials {
  const CaptiveLoginCredentials({required this.password});

  final String password;
}

class CaptiveLoginStore {
  CaptiveLoginStore._();

  static final CaptiveLoginStore instance = CaptiveLoginStore._();
  static const String defaultCampusSsid = 'Student-WiFi';
  static const String _passwordKey = 'wifi_captive_password';
  static const String _ssidKey = 'wifi_captive_ssid';
  static const String _autoExtendEnabledKey = 'wifi_captive_auto_extend';

  final TokenStorage _storage = TokenStorage.instance;

  Future<String> readSsid() async {
    return (await _storage.read(key: _ssidKey) ?? '').trim();
  }

  Future<void> saveSsid(String ssid) async {
    await _storage.write(key: _ssidKey, value: ssid);
  }

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

  static const String _lastPortalUrlKey = 'wifi_captive_last_portal_url';
  static const String _successUrlKey = 'wifi_captive_success_url';
  static const String _lastLoginAtKey = 'wifi_captive_last_login_at';

  Future<String?> readLastPortalUrl() async {
    return await _storage.read(key: _lastPortalUrlKey);
  }

  Future<void> saveLastPortalUrl(String url) async {
    await _storage.write(key: _lastPortalUrlKey, value: url);
  }

  Future<String?> readSuccessUrl() async {
    return await _storage.read(key: _successUrlKey);
  }

  Future<void> saveSuccessUrl(String url) async {
    await _storage.write(key: _successUrlKey, value: url);
  }

  Future<int?> readLastLoginAt() async {
    final raw = await _storage.read(key: _lastLoginAtKey);
    return raw != null ? int.tryParse(raw) : null;
  }

  Future<void> saveLastLoginAt(int timestamp) async {
    await _storage.write(key: _lastLoginAtKey, value: timestamp.toString());
  }

  Future<void> clear() async {
    await _storage.write(key: _passwordKey, value: null);
    await _storage.write(key: _autoExtendEnabledKey, value: null);
    await _storage.write(key: _lastPortalUrlKey, value: null);
    await _storage.write(key: _successUrlKey, value: null);
    await _storage.write(key: _lastLoginAtKey, value: null);
  }
}

class CoursePinStore {
  static String _key(String scope) => PreConnectPushConfig.coursePinsKey(scope);

  static Future<Set<String>> load(String scope) async {
    final localValues =
        (await AppStorage.instance.getStringList(_key(scope))) ??
        const <String>[];
    final values = <String>[...localValues];
    if (kIsWeb) {
      final mirrored = await _loadMirroredWebExtensionPins(scope);
      values.addAll(mirrored);
    }
    final normalized = values
        .map((e) => e.trim().toUpperCase())
        .where((e) => e.isNotEmpty)
        .toSet();
    if (kIsWeb && normalized.isNotEmpty) {
      await _saveMirroredWebExtensionPins(scope, normalized);
    }
    return normalized;
  }

  static Future<void> save(String scope, Set<String> pins) async {
    final values =
        pins
            .map((e) => e.trim().toUpperCase())
            .where((e) => e.isNotEmpty)
            .toList()
          ..sort();
    await AppStorage.instance.setStringList(_key(scope), values);
    if (kIsWeb) {
      await webExtensionStorageSet(_key(scope), jsonEncode(values));
    }
  }

  static Future<Set<String>> _loadMirroredWebExtensionPins(String scope) async {
    final raw = await webExtensionStorageGet(_key(scope));
    if (raw == null || raw.isEmpty) return const <String>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const <String>{};
      return decoded
          .map((value) => '$value'.trim().toUpperCase())
          .where((value) => value.isNotEmpty)
          .toSet();
    } catch (_) {
      return const <String>{};
    }
  }

  static Future<void> _saveMirroredWebExtensionPins(
    String scope,
    Set<String> pins,
  ) async {
    final values =
        pins
            .map((e) => e.trim().toUpperCase())
            .where((e) => e.isNotEmpty)
            .toList()
          ..sort();
    await webExtensionStorageSet(_key(scope), jsonEncode(values));
  }
}

class HomeCardPreferences {
  HomeCardPreferences._();

  static final decorationNotifier = ValueNotifier(true);

  static const String showQuickAccessSectionKey =
      'home_show_quick_access_section';
  static const String showRamadanCardKey = 'home_show_ramadan_card';
  static const String showExamCountdownCardKey =
      'home_show_exam_countdown_card';
  static const String showTodayScheduleKey = 'home_show_today_schedule';
  static const String showDecorationsKey = 'home_show_decorations';

  static const String showCampusMapContactsKey =
      'home_show_campus_map_contacts';
  static const String showNotificationsIconKey = 'home_show_notifications_icon';
  static const String showFundingSectionKey = 'home_show_funding_section';

  static const HomeCardVisibility defaults = HomeCardVisibility(
    showQuickAccessSection: true,
    showRamadanCard: true,
    showExamCountdownCard: true,
    showDecorations: true,
    showTodaySchedule: true,
    showCampusMapContacts: true,
    showNotificationsIcon: true,
    showFundingSection: true,
  );

  static Future<HomeCardVisibility> load() async {
    return loadSync();
  }

  static HomeCardVisibility loadSync() {
    try {
      final bool showDecorations =
          AppStorage.instance.getBoolSync(showDecorationsKey) ?? true;
      final bool showCampusMapContacts =
          AppStorage.instance.getBoolSync(showCampusMapContactsKey) ?? true;
      final bool showNotificationsIcon =
          AppStorage.instance.getBoolSync(showNotificationsIconKey) ?? true;

      decorationNotifier.value = showDecorations;

      return HomeCardVisibility(
        showQuickAccessSection:
            AppStorage.instance.getBoolSync(showQuickAccessSectionKey) ?? true,
        showDecorations: showDecorations,
        showRamadanCard:
            AppStorage.instance.getBoolSync(showRamadanCardKey) ?? true,
        showExamCountdownCard:
            AppStorage.instance.getBoolSync(showExamCountdownCardKey) ?? true,
        showTodaySchedule:
            AppStorage.instance.getBoolSync(showTodayScheduleKey) ?? true,
        showCampusMapContacts: showCampusMapContacts,
        showNotificationsIcon: showNotificationsIcon,
        showFundingSection:
            AppStorage.instance.getBoolSync(showFundingSectionKey) ?? true,
      );
    } catch (_) {
      return defaults;
    }
  }

  static Future<void> setShowRamadanCard(bool value) async {
    try {
      await AppStorage.instance.setBool(showRamadanCardKey, value);
    } catch (_) {}
  }

  static Future<void> setShowDecorations(bool value) async {
    try {
      decorationNotifier.value = value;
      await AppStorage.instance.setBool(showDecorationsKey, value);
    } catch (_) {}
  }

  static Future<void> setShowExamCountdownCard(bool value) async {
    try {
      await AppStorage.instance.setBool(showExamCountdownCardKey, value);
    } catch (_) {}
  }

  static Future<void> setShowQuickAccessSection(bool value) async {
    try {
      await AppStorage.instance.setBool(showQuickAccessSectionKey, value);
    } catch (_) {}
  }

  static Future<void> setShowTodaySchedule(bool value) async {
    try {
      await AppStorage.instance.setBool(showTodayScheduleKey, value);
    } catch (_) {}
  }

  static Future<void> setShowCampusMapContacts(bool value) async {
    try {
      await AppStorage.instance.setBool(showCampusMapContactsKey, value);
    } catch (_) {}
  }

  static Future<void> setShowNotificationsIcon(bool value) async {
    try {
      await AppStorage.instance.setBool(showNotificationsIconKey, value);
    } catch (_) {}
  }

  static Future<void> setShowFundingSection(bool value) async {
    try {
      await AppStorage.instance.setBool(showFundingSectionKey, value);
    } catch (_) {}
  }
}

class HomeCardVisibility {
  const HomeCardVisibility({
    required this.showQuickAccessSection,
    required this.showRamadanCard,
    required this.showDecorations,
    required this.showExamCountdownCard,
    required this.showTodaySchedule,
    required this.showCampusMapContacts,
    required this.showNotificationsIcon,
    required this.showFundingSection,
  });

  final bool showDecorations;
  final bool showQuickAccessSection;
  final bool showRamadanCard;
  final bool showExamCountdownCard;
  final bool showTodaySchedule;
  final bool showCampusMapContacts;
  final bool showNotificationsIcon;
  final bool showFundingSection;
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

      final prefs = AppStorage.instance;
      final now = DateTime.now().toUtc();

      final launches = (await prefs.getInt(_launchCountKey) ?? 0) + 1;
      await prefs.setInt(_launchCountKey, launches);

      final hasFirstOpen = await prefs.containsKey(_firstOpenKey);
      final firstOpenMs =
          await prefs.getInt(_firstOpenKey) ?? now.millisecondsSinceEpoch;
      if (!hasFirstOpen) {
        await prefs.setInt(_firstOpenKey, firstOpenMs);
      }
      final firstOpen = DateTime.fromMillisecondsSinceEpoch(
        firstOpenMs,
        isUtc: true,
      );

      final lastPromptMs = await prefs.getInt(_lastPromptKey);
      final lastAttemptMs = await prefs.getInt(_lastAttemptKey);

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
      if (kIsWeb) {
        final uri = Uri.parse(
          'https://play.google.com/store/apps/details?id=com.sabbirba.preconnect',
        );
        return await launchUrl(uri, mode: LaunchMode.externalApplication);
      }

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
      return true;
    }

    return true;
  }
}

class AppLockService {
  static const String _prefsKey = 'app_lock_enabled';
  final LocalAuthentication _auth = LocalAuthentication();

  Future<bool> isEnabled() async {
    return await AppStorage.instance.getBool(_prefsKey) ?? false;
  }

  Future<void> setEnabled(bool value) async {
    await AppStorage.instance.setBool(_prefsKey, value);
  }

  Future<bool> authenticate({String reason = ''}) async {
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

  Future<bool> isBiometricAvailable() async {
    try {
      final canCheck = await _auth.canCheckBiometrics;
      final isSupported = await _auth.isDeviceSupported();
      if (!canCheck && !isSupported) return false;

      final available = await _auth.getAvailableBiometrics();
      return available.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<bool> authenticateBiometricOnly({String reason = ''}) async {
    try {
      if (!await isBiometricAvailable()) return false;
      return await _auth.authenticate(
        localizedReason: reason,
        biometricOnly: true,
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

    final dir = await AppPaths.supportDirectory();
    final file = File('${dir.path}/profile_photo.jpg');

    final cachedUrl = await AppStorage.instance.getString(_cachedUrlKey);
    await AppStorage.instance.remove(_legacyCachedBytesKey);

    if (file.existsSync() &&
        file.lengthSync() > 0 &&
        (cachedUrl == null || cachedUrl == photoUrl)) {
      _cachedFile = file;
      return file;
    }

    try {
      final uri = Uri.parse(photoUrl);
      final headers = <String, String>{
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/125.0 Safari/537.36',
      };
      if (uri.host == 'connect.bracu.ac.bd') {
        final token = await TokenStorage.instance.read(key: PreConnectStorageKeys.accessToken);
        if (token != null && token.isNotEmpty) {
          headers['Authorization'] = 'Bearer $token';
        }
        final idToken = await TokenStorage.instance.read(key: PreConnectStorageKeys.idToken);
        if (idToken != null && idToken.isNotEmpty) {
          headers['X-ID-Token'] = idToken;
        }
      }
      headers.addAll(compressionHeadersForUri(uri));
      final response = await HttpUtils.client.get(
        uri,
        headers: headers,
      );
      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        await file.writeAsBytes(response.bodyBytes, flush: true);
        await AppStorage.instance.setString(_cachedUrlKey, photoUrl);
        _cachedFile = file;
        return file;
      }
    } catch (_) {}

    return null;
  }

  void invalidate() {
    _cachedFile = null;
  }

  Future<void> clear() async {
    try {
      final dir = await AppPaths.supportDirectory();
      final file = File('${dir.path}/profile_photo.jpg');
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
    await AppStorage.instance.remove(_cachedUrlKey);
    await AppStorage.instance.remove(_legacyCachedBytesKey);
    _cachedFile = null;
  }
}
