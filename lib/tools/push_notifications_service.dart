import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:preconnect/api/seat_alert_push_service.dart';
import 'package:preconnect/api/seat_status_service.dart';
import 'package:preconnect/firebase_options.dart';
import 'package:preconnect/tools/build_info.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (_) {}
  try {
    await SeatAlertPushService().handleIncomingSeatAlertPayload(message.data);
  } catch (_) {}
}

class PushNotificationsService {
  PushNotificationsService._internal();

  static final PushNotificationsService _instance =
      PushNotificationsService._internal();
  factory PushNotificationsService() => _instance;

  bool _initialized = false;
  StreamSubscription<String>? _tokenRefreshSubscription;
  StreamSubscription<RemoteMessage>? _messageOpenedSubscription;

  Future<void> initialize() async {
    if (_initialized || !_isSupportedPlatform) return;
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    final messaging = FirebaseMessaging.instance;
    await messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    await _syncCurrentTokenIfAuthorized();
    _tokenRefreshSubscription = messaging.onTokenRefresh.listen((token) {
      unawaited(_syncTokenIfAuthorized(token));
    });
    _messageOpenedSubscription = FirebaseMessaging.onMessageOpenedApp.listen((
      message,
    ) {
      unawaited(
        SeatAlertPushService().handleIncomingSeatAlertPayload(message.data),
      );
    });
    final initialMessage = await messaging.getInitialMessage();
    if (initialMessage != null) {
      await SeatAlertPushService().handleIncomingSeatAlertPayload(
        initialMessage.data,
      );
    }
    _initialized = true;
  }

  Future<bool> hasNotificationPermission() async {
    if (!_isSupportedPlatform) return false;
    await _ensureFirebaseInitialized();
    final settings = await FirebaseMessaging.instance.getNotificationSettings();
    return settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
  }

  Future<bool> ensureNotificationPermission() async {
    if (!_isSupportedPlatform) return false;
    await _ensureFirebaseInitialized();
    if (await hasNotificationPermission()) {
      await _syncCurrentTokenIfAuthorized();
      return true;
    }

    final settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    final granted =
        settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
    if (granted) {
      await _syncCurrentTokenIfAuthorized();
    }
    return granted;
  }

  Future<bool> openSystemNotificationSettings() async {
    if (!_isSupportedPlatform) return false;
    return openAppSettings();
  }

  Future<void> dispose() async {
    await _tokenRefreshSubscription?.cancel();
    await _messageOpenedSubscription?.cancel();
    _tokenRefreshSubscription = null;
    _messageOpenedSubscription = null;
    _initialized = false;
  }

  bool get _isSupportedPlatform {
    if (kIsWeb) return false;
    final platform = defaultTargetPlatform;
    return platform == TargetPlatform.android || platform == TargetPlatform.iOS;
  }

  Future<void> _ensureFirebaseInitialized() async {
    try {
      Firebase.app();
    } catch (_) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
  }

  Future<void> _syncCurrentTokenIfAuthorized() async {
    if (!await hasNotificationPermission()) return;
    final token = await FirebaseMessaging.instance.getToken();
    await _syncToken(token);
  }

  Future<void> _syncTokenIfAuthorized(String? token) async {
    if (!await hasNotificationPermission()) return;
    await _syncToken(token);
  }

  Future<void> _syncToken(String? token) async {
    final normalized = (token ?? '').trim();
    if (normalized.isEmpty) return;
    final locale = WidgetsBinding.instance.platformDispatcher.locale
        .toLanguageTag();
    final appVersion = await BuildInfo.fullVersion();
    await SeatAlertPushService().configureDeviceToken(normalized);
    try {
      await SeatAlertPushService().registerDevice(
        platform: defaultTargetPlatform == TargetPlatform.iOS
            ? 'ios'
            : 'android',
        locale: locale,
        appVersion: appVersion,
      );
      final configs = await SeatStatusService().loadSeatAlertConfigs();
      await SeatAlertPushService().syncAllSeatAlertConfigs(configs);
    } catch (_) {}
  }
}
