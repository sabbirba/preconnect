import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import 'package:flutter/foundation.dart'
    show
        ValueNotifier,
        defaultTargetPlatform,
        kIsWeb,
        kReleaseMode,
        TargetPlatform;

import 'package:local_auth/local_auth.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:preconnect/tools/app_storage.dart';
import 'package:preconnect/tools/preconnect_constants.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:preconnect/tools/platform_stub.dart'
    if (dart.library.js_interop) 'package:preconnect/tools/storage_web.dart';
import 'package:preconnect/tools/http/http_headers.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:preconnect/tools/store_actions.dart';

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
    PreConnectStorageKeys.idToken,
    'wifi_captive_password',
  };

  static const _secureStorage = FlutterSecureStorage(
    mOptions: MacOsOptions(usesDataProtectionKeychain: kReleaseMode),
  );

  Future<void>? _legacyMigration;

  Future<String?> read({required String key}) async {
    if (kIsWeb) {
      try {
        return await webExtensionStorageGet(key);
      } catch (error) {
        throw TokenPersistenceException(
          'Failed to read browser storage for "$key" '
          '(${error.runtimeType}).',
        );
      }
    }

    if (_sensitiveKeys.contains(key)) {
      await _ensureLegacySensitiveValuesMigrated();
      return _readSecureValue(key);
    }

    final value = await AppStorage.instance.getString(key);
    if (value == null || value.isEmpty) return null;
    return value;
  }

  Future<bool> hasAccessToken() async {
    final value = await read(key: PreConnectStorageKeys.accessToken);
    return value != null && value.isNotEmpty;
  }

  Future<void> write({required String key, String? value}) async {
    if (kIsWeb) {
      try {
        await webExtensionStorageSet(key, value);
      } catch (error) {
        throw TokenPersistenceException(
          'Failed to write browser storage for "$key" '
          '(${error.runtimeType}).',
        );
      }
      await _updateCachedSessionFlagForKey(key, value);
      return;
    }

    if (_sensitiveKeys.contains(key)) {
      await _ensureLegacySensitiveValuesMigrated();
      await _writeSecureValue(key, value);
      await _removeLegacyValue(key);
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
    if (!kIsWeb) {
      await _ensureLegacySensitiveValuesMigrated();
      for (final key in _sensitiveKeys) {
        await _writeSecureValue(key, null);
        await _removeLegacyValue(key);
      }
    } else {
      for (final key in _sensitiveKeys) {
        await AppStorage.instance.remove(key);
      }
    }

    await AppStorage.instance.setBool(_cachedHasSessionKey, false);
    if (kIsWeb) {
      try {
        await webExtensionStorageRemoveKeys(const [
          PreConnectStorageKeys.accessToken,
          PreConnectStorageKeys.refreshToken,
          PreConnectStorageKeys.idToken,
          'wifi_captive_password',
          _cachedHasSessionKey,
        ]);
      } catch (error) {
        throw TokenPersistenceException(
          'Failed to delete browser storage (${error.runtimeType}).',
        );
      }
    }
  }

  Future<void> _updateCachedSessionFlagForKey(String key, String? value) async {
    if (key != PreConnectStorageKeys.accessToken) return;
    final hasValue = value != null && value.isNotEmpty;
    await AppStorage.instance.setBool(_cachedHasSessionKey, hasValue);
  }

  Future<void> _ensureLegacySensitiveValuesMigrated() async {
    final inFlight = _legacyMigration;
    if (inFlight != null) {
      return inFlight;
    }

    final migration = _migrateLegacySensitiveValues();
    _legacyMigration = migration;
    try {
      await migration;
    } catch (_) {
      if (identical(_legacyMigration, migration)) {
        _legacyMigration = null;
      }
      rethrow;
    }
  }

  Future<void> _migrateLegacySensitiveValues() async {
    for (final key in _sensitiveKeys) {
      final String? legacyValue;
      try {
        legacyValue = await AppStorage.instance.getString(key);
      } catch (error) {
        throw TokenPersistenceException(
          'Failed to read legacy storage for "$key" '
          '(${error.runtimeType}).',
        );
      }

      if (legacyValue == null) {
        continue;
      }

      final secureValue = await _readSecureValue(key);
      if ((secureValue == null || secureValue.isEmpty) &&
          legacyValue.isNotEmpty) {
        await _writeSecureValue(key, legacyValue);
      }
      await _removeLegacyValue(key);
    }
  }

  Future<String?> _readSecureValue(String key) async {
    try {
      final value = await _secureStorage.read(key: key);
      if (value == null || value.isEmpty) return null;
      return value;
    } catch (error) {
      throw TokenPersistenceException(
        'Failed to read secure storage for "$key" '
        '(${error.runtimeType}).',
      );
    }
  }

  Future<void> _writeSecureValue(String key, String? value) async {
    try {
      if (value == null || value.isEmpty) {
        await _secureStorage.delete(key: key);
      } else {
        await _secureStorage.write(key: key, value: value);
      }
    } catch (error) {
      final operation = value == null || value.isEmpty ? 'delete' : 'write';
      throw TokenPersistenceException(
        'Failed to $operation secure storage for "$key" '
        '(${error.runtimeType}).',
      );
    }
  }

  Future<void> _removeLegacyValue(String key) async {
    try {
      await AppStorage.instance.remove(key);
      if (await AppStorage.instance.containsKey(key)) {
        throw StateError('Legacy value still exists after removal.');
      }
    } catch (error) {
      throw TokenPersistenceException(
        'Failed to remove legacy storage for "$key" '
        '(${error.runtimeType}).',
      );
    }
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

  Future<String?> readLastPortalUrl() {
    return _storage.read(key: _lastPortalUrlKey);
  }

  Future<void> saveLastPortalUrl(String url) async {
    await _storage.write(key: _lastPortalUrlKey, value: url);
  }

  Future<String?> readSuccessUrl() {
    return _storage.read(key: _successUrlKey);
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

      if (decorationNotifier.value != showDecorations) {
        scheduleMicrotask(() {
          decorationNotifier.value = showDecorations;
        });
      }

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

  static Future<void> setShowRamadanCard(bool value) {
    return AppStorage.instance.setBool(showRamadanCardKey, value);
  }

  static Future<void> setShowDecorations(bool value) async {
    decorationNotifier.value = value;
    await AppStorage.instance.setBool(showDecorationsKey, value);
  }

  static Future<void> setShowExamCountdownCard(bool value) {
    return AppStorage.instance.setBool(showExamCountdownCardKey, value);
  }

  static Future<void> setShowQuickAccessSection(bool value) {
    return AppStorage.instance.setBool(showQuickAccessSectionKey, value);
  }

  static Future<void> setShowTodaySchedule(bool value) {
    return AppStorage.instance.setBool(showTodayScheduleKey, value);
  }

  static Future<void> setShowCampusMapContacts(bool value) {
    return AppStorage.instance.setBool(showCampusMapContactsKey, value);
  }

  static Future<void> setShowNotificationsIcon(bool value) {
    return AppStorage.instance.setBool(showNotificationsIconKey, value);
  }

  static Future<void> setShowFundingSection(bool value) {
    return AppStorage.instance.setBool(showFundingSectionKey, value);
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

      final available = await StoreActions.isReviewAvailable();
      if (!available) return;
      await StoreActions.requestReview();
      await prefs.setInt(_lastPromptKey, now.millisecondsSinceEpoch);
    } catch (_) {}
  }

  static Future<bool> openStoreListing({String? iosAppStoreId}) async {
    try {
      if (!kIsWeb) {
        try {
          final reviewAvailable = await StoreActions.isReviewAvailable();
          if (reviewAvailable) {
            unawaited(StoreActions.requestReview());
          }
        } catch (_) {}
      }

      if (kIsWeb) {
        final playStoreUri = Uri.parse(
          'https://play.google.com/store/apps/details?id=com.sabbirba.preconnect',
        );
        try {
          final launched = await launchUrl(
            playStoreUri,
            mode: LaunchMode.externalApplication,
          );
          if (launched) return true;
        } catch (_) {}
        try {
          return await launchUrl(
            playStoreUri,
            mode: LaunchMode.platformDefault,
          );
        } catch (_) {
          return false;
        }
      }

      final isApple =
          !kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.iOS ||
              defaultTargetPlatform == TargetPlatform.macOS);

      if (isApple) {
        var appStoreId = (iosAppStoreId ?? '').trim();
        if (appStoreId.isEmpty) {
          try {
            final packageInfo = await PackageInfo.fromPlatform();
            final bundleId = packageInfo.packageName;
            final response = await http
                .get(
                  Uri.parse(
                    'https://itunes.apple.com/lookup?bundleId=$bundleId',
                  ),
                )
                .timeout(const Duration(seconds: 3));
            if (response.statusCode == 200) {
              final data = jsonDecode(response.body);
              if (data != null &&
                  data['resultCount'] != null &&
                  data['resultCount'] > 0) {
                final results = data['results'] as List<dynamic>;
                if (results.isNotEmpty && results[0]['trackId'] != null) {
                  appStoreId = results[0]['trackId'].toString();
                }
              }
            }
          } catch (_) {}
        }

        if (appStoreId.isNotEmpty) {
          final nativeItmsUri = Uri.parse(
            'itms-apps://itunes.apple.com/app/id$appStoreId?action=write-review',
          );
          try {
            final launched = await launchUrl(
              nativeItmsUri,
              mode: LaunchMode.externalApplication,
            );
            if (launched) return true;
          } catch (_) {}

          final httpsAppStoreUri = Uri.parse(
            'https://apps.apple.com/app/id$appStoreId?action=write-review',
          );
          try {
            final launched = await launchUrl(
              httpsAppStoreUri,
              mode: LaunchMode.externalApplication,
            );
            if (launched) return true;
          } catch (_) {}
        }

        final fallbackAppStoreUri = Uri.parse(
          'https://apps.apple.com/app/id6503926521',
        );
        try {
          final launched = await launchUrl(
            fallbackAppStoreUri,
            mode: LaunchMode.externalApplication,
          );
          if (launched) return true;
        } catch (_) {}

        return await launchUrl(
          fallbackAppStoreUri,
          mode: LaunchMode.platformDefault,
        );
      }

      var packageName = 'com.sabbirba.preconnect';
      try {
        final packageInfo = await PackageInfo.fromPlatform();
        if (packageInfo.packageName.isNotEmpty) {
          packageName = packageInfo.packageName;
        }
      } catch (_) {}

      final marketUri = Uri.parse('market://details?id=$packageName');
      try {
        final launched = await launchUrl(
          marketUri,
          mode: LaunchMode.externalApplication,
        );
        if (launched) return true;
      } catch (_) {}

      final playStoreUri = Uri.parse(
        'https://play.google.com/store/apps/details?id=$packageName',
      );
      try {
        final launched = await launchUrl(
          playStoreUri,
          mode: LaunchMode.externalApplication,
        );
        if (launched) return true;
      } catch (_) {}

      try {
        return await launchUrl(playStoreUri, mode: LaunchMode.platformDefault);
      } catch (_) {}

      return false;
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
        localizedReason: reason.isEmpty
            ? 'Authenticate to unlock PreConnect'
            : reason,
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
        localizedReason: reason.isEmpty
            ? 'Authenticate to unlock PreConnect'
            : reason,
        biometricOnly: true,
        sensitiveTransaction: true,
        persistAcrossBackgrounding: true,
      );
    } catch (_) {
      return false;
    }
  }
}

Future<bool> looksLikeImageFile(File file) async {
  try {
    final raf = await file.open();
    final header = await raf.read(12);
    await raf.close();
    if (header.length >= 3 &&
        header[0] == 0xFF &&
        header[1] == 0xD8 &&
        header[2] == 0xFF) {
      return true;
    }
    if (header.length >= 4 &&
        header[0] == 0x89 &&
        header[1] == 0x50 &&
        header[2] == 0x4E &&
        header[3] == 0x47) {
      return true;
    }
    if (header.length >= 3 &&
        header[0] == 0x47 &&
        header[1] == 0x49 &&
        header[2] == 0x46) {
      return true;
    }
    if (header.length >= 2 && header[0] == 0x42 && header[1] == 0x4D) {
      return true;
    }
    if (header.length >= 12 &&
        header[0] == 0x52 &&
        header[1] == 0x49 &&
        header[2] == 0x46 &&
        header[3] == 0x46 &&
        header[8] == 0x57 &&
        header[9] == 0x45 &&
        header[10] == 0x42 &&
        header[11] == 0x50) {
      return true;
    }
    return false;
  } catch (_) {
    return false;
  }
}

class ProfileImageCache {
  ProfileImageCache._();
  static final instance = ProfileImageCache._();

  static const _cacheKey = 'profile_image_cache';
  static final Map<String, File> _memCache = <String, File>{};

  final CacheManager _cacheManager = CacheManager(
    Config(
      _cacheKey,
      stalePeriod: const Duration(days: 90),
      maxNrOfCacheObjects: 50,
    ),
  );

  File? getFromMemory(String? photoUrl) {
    if (photoUrl == null || photoUrl.isEmpty) return null;
    return _memCache[photoUrl];
  }

  Future<File?> getProfileImage(String? photoUrl) async {
    if (photoUrl == null || photoUrl.isEmpty) return null;

    final mem = _memCache[photoUrl];
    if (mem != null) return mem;

    try {
      final cached = await _cacheManager.getFileFromCache(photoUrl);
      if (cached != null && await looksLikeImageFile(cached.file)) {
        _memCache[photoUrl] = cached.file;
        return cached.file;
      }
    } catch (_) {}

    try {
      final uri = Uri.parse(photoUrl);
      final headers = <String, String>{
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/125.0 Safari/537.36',
      };
      if (uri.host == 'connect.bracu.ac.bd') {
        final token = await TokenStorage.instance.read(
          key: PreConnectStorageKeys.accessToken,
        );
        if (token != null && token.isNotEmpty) {
          headers['Authorization'] = 'Bearer $token';
        }
        final idToken = await TokenStorage.instance.read(
          key: PreConnectStorageKeys.idToken,
        );
        if (idToken != null && idToken.isNotEmpty) {
          headers['X-ID-Token'] = idToken;
        }
      }
      headers.addAll(compressionHeadersForUri(uri));
      final fileInfo = await _cacheManager.downloadFile(
        photoUrl,
        authHeaders: headers,
      );
      if (await looksLikeImageFile(fileInfo.file)) {
        _memCache[photoUrl] = fileInfo.file;
        return fileInfo.file;
      }
    } catch (_) {}

    return null;
  }

  void invalidate() {
    _memCache.clear();
  }

  Future<void> clear() async {
    _memCache.clear();
    await _cacheManager.emptyCache();
  }
}
