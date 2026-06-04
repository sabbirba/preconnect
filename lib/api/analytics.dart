import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';

class AnalyticsService {
  AnalyticsService._();

  static final AnalyticsService instance = AnalyticsService._();

  final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;

  static FirebaseAnalyticsObserver get observer =>
      FirebaseAnalyticsObserver(analytics: FirebaseAnalytics.instance);

  Future<void> logScreenView(String screenName) async {
    try {
      await _analytics.logScreenView(screenName: screenName);
      if (kDebugMode) debugPrint('[Analytics] screen_view: $screenName');
    } catch (_) {}
  }

  Future<void> logEvent(String name, {Map<String, Object>? params}) async {
    try {
      await _analytics.logEvent(name: name, parameters: params);
      if (kDebugMode) debugPrint('[Analytics] event: $name | params: $params');
    } catch (_) {}
  }

  Future<void> logFeatureUsed(String featureName) async {
    try {
      await _analytics.logEvent(
        name: 'feature_used',
        parameters: <String, Object>{'feature': featureName},
      );
      if (kDebugMode) debugPrint('[Analytics] feature_used: $featureName');
    } catch (_) {}
  }
}
