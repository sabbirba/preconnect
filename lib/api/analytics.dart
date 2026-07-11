import 'package:firebase_analytics/firebase_analytics.dart';

class AnalyticsService {
  AnalyticsService._();

  static final AnalyticsService instance = AnalyticsService._();

  final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;

  static FirebaseAnalyticsObserver get observer =>
      FirebaseAnalyticsObserver(analytics: FirebaseAnalytics.instance);

  Future<void> logScreenView(String screenName) async {
    try {
      await _analytics.logScreenView(screenName: screenName);
    } catch (_) {}
  }

  Future<void> logEvent(String name, {Map<String, Object>? params}) async {
    try {
      await _analytics.logEvent(name: name, parameters: params);
    } catch (_) {}
  }

  Future<void> logFeatureUsed(String featureName) async {
    try {
      await _analytics.logEvent(
        name: 'feature_used',
        parameters: <String, Object>{'feature': featureName},
      );
    } catch (_) {}
  }
}
