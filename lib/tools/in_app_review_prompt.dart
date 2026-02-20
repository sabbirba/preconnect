import 'dart:io';
import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
      if (!available) {
        final openedStore = await openStoreListing();
        if (openedStore) {
          await prefs.setInt(_lastPromptKey, now.millisecondsSinceEpoch);
        }
        return;
      }
      await inAppReview.requestReview();
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
