import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart'
    show ValueNotifier, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart' show TargetPlatform;
import 'package:flutter/services.dart';
import 'package:preconnect/tools/http/http_service.dart';

import 'package:in_app_review/in_app_review.dart';
import 'package:local_auth/local_auth.dart';
import 'package:preconnect/api/api_client.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:preconnect/tools/app_storage.dart';
import 'package:preconnect/tools/app_paths.dart';
import 'package:preconnect/tools/preconnect_constants.dart';
import 'package:preconnect/tools/web_platform_stub.dart'
    if (dart.library.html) 'package:preconnect/tools/web_extension_storage_web.dart';

class TokenPersistenceException implements Exception {
  TokenPersistenceException(this.message);
  final String message;

  @override
  String toString() => 'TokenPersistenceException: $message';
}

class AdsPreferences {
  AdsPreferences._();

  static final AdsPreferences instance = AdsPreferences._();
  static const String hideAdsKey = 'hide_ads';
  final ValueNotifier<bool> adsVisible = ValueNotifier<bool>(true);

  Future<void> load() async {
    try {
      final hidden = await AppStorage.instance.getBool(hideAdsKey) ?? false;
      adsVisible.value = !hidden;
    } catch (_) {}
  }

  bool get isVisible => adsVisible.value;
  bool get isHidden => !adsVisible.value;

  Future<void> setHidden(bool hidden) async {
    try {
      await load();
      await AppStorage.instance.setBool(hideAdsKey, hidden);
      adsVisible.value = !hidden;
    } catch (_) {}
  }
}

class TokenStorage {
  TokenStorage._();

  static final TokenStorage instance = TokenStorage._();
  static const String _cachedHasSessionKey =
      PreconnectStorageKeys.cachedHasAuthSession;

  Future<String?> read({required String key}) async {
    if (kIsWeb) {
      return await webExtensionStorageGet(key);
    }

    final value = await AppStorage.instance.getString(key);
    if (value == null || value.isEmpty) return null;
    return value;
  }

  Future<bool> hasAccessToken() async {
    final value = await read(key: PreconnectStorageKeys.accessToken);
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

    if (value == null || value.isEmpty) {
      await AppStorage.instance.remove(key);
    } else {
      await AppStorage.instance.setString(key, value);
    }

    await _updateCachedSessionFlagForKey(key, value);
  }

  Future<void> deleteAll() async {
    await AppStorage.instance.remove(PreconnectStorageKeys.accessToken);
    await AppStorage.instance.remove(PreconnectStorageKeys.refreshToken);
    await AppStorage.instance.setBool(_cachedHasSessionKey, false);

    if (kIsWeb) {
      await webExtensionStorageRemoveKeys(const [
        PreconnectStorageKeys.accessToken,
        PreconnectStorageKeys.refreshToken,
        _cachedHasSessionKey,
      ]);
    }
  }

  Future<void> _updateCachedSessionFlagForKey(String key, String? value) async {
    if (key != PreconnectStorageKeys.accessToken) return;
    final hasValue = value != null && value.isNotEmpty;
    await AppStorage.instance.setBool(_cachedHasSessionKey, hasValue);
  }
}

const String kPreconnectUserAgent =
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
    final values =
        (await AppStorage.instance.getStringList(_key(scope))) ??
        const <String>[];
    return values
        .map((e) => e.trim().toUpperCase())
        .where((e) => e.isNotEmpty)
        .toSet();
  }

  static Future<void> save(String scope, Set<String> pins) async {
    final values =
        pins
            .map((e) => e.trim().toUpperCase())
            .where((e) => e.isNotEmpty)
            .toList()
          ..sort();
    await AppStorage.instance.setStringList(_key(scope), values);
  }
}

class HomeCardPreferences {
  HomeCardPreferences._();

  static final decorationNotifier = ValueNotifier(true);
  static final sponsoredContentNotifier = ValueNotifier(true);
  static final communityLinkNotifier = ValueNotifier(true);

  static const String showQuickAccessSectionKey =
      'home_show_quick_access_section';
  static const String showRamadanCardKey = 'home_show_ramadan_card';
  static const String showExamCountdownCardKey =
      'home_show_exam_countdown_card';
  static const String showTodayScheduleKey = 'home_show_today_schedule';
  static const String showSponsoredContentKey = 'home_show_sponsored_content';
  static const String showDecorationsKey = 'home_show_decorations';
  static const String showCommunityLinkKey = 'home_show_community_link';
  static const String showCampusMapContactsKey =
      'home_show_campus_map_contacts';
  static const String showNotificationsIconKey = 'home_show_notifications_icon';

  static const HomeCardVisibility defaults = HomeCardVisibility(
    showQuickAccessSection: true,
    showRamadanCard: true,
    showExamCountdownCard: true,
    showDecorations: true,
    showTodaySchedule: true,
    showSponsoredContent: true,
    showCommunityLink: true,
    showCampusMapContacts: true,
    showNotificationsIcon: true,
  );

  static Future<HomeCardVisibility> load() async {
    try {
      final bool showDecorations =
          await AppStorage.instance.getBool(showDecorationsKey) ?? true;
      final bool showSponsoredContent =
          await AppStorage.instance.getBool(showSponsoredContentKey) ?? true;
      final bool showCommunityLink =
          await AppStorage.instance.getBool(showCommunityLinkKey) ?? true;
      final bool showCampusMapContacts =
          await AppStorage.instance.getBool(showCampusMapContactsKey) ?? true;
      final bool showNotificationsIcon =
          await AppStorage.instance.getBool(showNotificationsIconKey) ?? true;

      decorationNotifier.value = showDecorations;
      sponsoredContentNotifier.value = showSponsoredContent;
      communityLinkNotifier.value = showCommunityLink;

      return HomeCardVisibility(
        showQuickAccessSection:
            await AppStorage.instance.getBool(showQuickAccessSectionKey) ??
            true,
        showDecorations: showDecorations,
        showRamadanCard:
            await AppStorage.instance.getBool(showRamadanCardKey) ?? true,
        showExamCountdownCard:
            await AppStorage.instance.getBool(showExamCountdownCardKey) ?? true,
        showTodaySchedule:
            await AppStorage.instance.getBool(showTodayScheduleKey) ?? true,
        showSponsoredContent: showSponsoredContent,
        showCommunityLink: showCommunityLink,
        showCampusMapContacts: showCampusMapContacts,
        showNotificationsIcon: showNotificationsIcon,
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

  static Future<void> setShowCommunityLink(bool value) async {
    try {
      communityLinkNotifier.value = value;
      await AppStorage.instance.setBool(showCommunityLinkKey, value);
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

  static Future<void> setShowSponsoredContent(bool value) async {
    try {
      sponsoredContentNotifier.value = value;
      await AppStorage.instance.setBool(showSponsoredContentKey, value);
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
}

class HomeCardVisibility {
  const HomeCardVisibility({
    required this.showQuickAccessSection,
    required this.showRamadanCard,
    required this.showDecorations,
    required this.showExamCountdownCard,
    required this.showTodaySchedule,
    required this.showSponsoredContent,
    required this.showCommunityLink,
    required this.showCampusMapContacts,
    required this.showNotificationsIcon,
  });

  final bool showDecorations;
  final bool showQuickAccessSection;
  final bool showRamadanCard;
  final bool showExamCountdownCard;
  final bool showTodaySchedule;
  final bool showSponsoredContent;
  final bool showCommunityLink;
  final bool showCampusMapContacts;
  final bool showNotificationsIcon;
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
      final response = await HttpService.client.get(
        uri,
        headers: compressionHeadersForUri(uri),
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
