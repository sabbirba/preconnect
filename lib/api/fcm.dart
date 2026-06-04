import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:preconnect/api/api_client.dart';
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/tools/preconnect_constants.dart';
import 'package:preconnect/tools/refresh_bus.dart';
import 'package:preconnect/tools/token_storage.dart';
import 'package:preconnect/tools/web_extension_push_sync_stub.dart'
    if (dart.library.html) 'package:preconnect/tools/web_extension_push_sync_web.dart';
import 'package:preconnect/tools/chrome_runtime_available_stub.dart'
    if (dart.library.html) 'package:preconnect/tools/chrome_runtime_available_web.dart';
import 'package:url_launcher/url_launcher.dart';

class FCMService {
  FCMService._();

  static final FCMService instance = FCMService._();
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  bool _apnsAvailable = true;

  bool get isSupported {
    if (kIsWeb) {
      return isChromeRuntimeAvailable();
    }
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  @pragma('vm:entry-point')
  static Future<void> backgroundHandler(RemoteMessage message) async {
    await Firebase.initializeApp();
    debugPrint("Background message: ${message.messageId}");
  }

  Future<String?> _getToken() async {
    if (kIsWeb) {
      var token = await TokenStorage.instance.read(
        key: PreconnectPushConfig.gcmTokenKey,
      );
      if (token == null || token.isEmpty) {
        await requestWebExtensionPushTokenSync();
        for (var attempt = 0; attempt < 5; attempt++) {
          await Future<void>.delayed(const Duration(milliseconds: 200));
          token = await TokenStorage.instance.read(
            key: PreconnectPushConfig.gcmTokenKey,
          );
          if (token != null && token.isNotEmpty) break;
        }
      }
      debugPrint("FCM Web Token: $token");
      return token;
    }
    try {
      if (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS) {
        String? apnsToken;
        int retries = 0;
        final isAppleDebug =
            (defaultTargetPlatform == TargetPlatform.macOS ||
                defaultTargetPlatform == TargetPlatform.iOS) &&
            kDebugMode;
        final maxRetries = isAppleDebug ? 1 : 10;

        while (apnsToken == null && retries < maxRetries) {
          apnsToken = await FirebaseMessaging.instance.getAPNSToken();
          debugPrint("FCM APNS Token try $retries: $apnsToken");
          if (apnsToken == null) {
            await Future.delayed(const Duration(seconds: 1));
            retries++;
          }
        }

        if (apnsToken == null) {
          _apnsAvailable = false;
          debugPrint(
            "FCM Error: Failed to get APNS token after retries. Push notifications will not work.",
          );
          return null;
        } else {
          _apnsAvailable = true;
        }
      }
      final token = await FirebaseMessaging.instance.getToken();
      debugPrint("FCM Token: $token");
      return token;
    } catch (e) {
      debugPrint("FCM Error getting token: $e");
      return null;
    }
  }

  Future<void> _sendTokenToBackend(String token) async {
    try {
      final client = ApiClient();
      if (!await client.hasAccessToken()) return;
      final url =
          '${ApiConfig.realtimeApiBase}${PreconnectPushConfig.registerDevicePath}';
      await client.authenticatedRequest(
        'POST',
        url,
        body: jsonEncode(<String, dynamic>{
          'token': token,
          'platform': kIsWeb
              ? PreconnectPushConfig.chromeExtensionPlatform
              : defaultTargetPlatform.name.toLowerCase(),
        }),
        additionalHeaders: const <String, String>{
          'Content-Type': 'application/json',
        },
      );
    } catch (e) {
      debugPrint("FCM token registration failed: $e");
    }
  }

  Future<void> _syncToken() async {
    final token = await _getToken();

    if (token != null) {
      await _sendTokenToBackend(token);
    }
  }

  Future<void> _subscribeToTopicWeb(String token, String topic) async {
    try {
      final client = ApiClient();
      if (!await client.hasAccessToken()) return;
      final url =
          '${ApiConfig.realtimeApiBase}${PreconnectPushConfig.subscribeTopicPath}';
      await client.authenticatedRequest(
        'POST',
        url,
        body: jsonEncode(<String, dynamic>{'token': token, 'topic': topic}),
        additionalHeaders: const <String, String>{
          'Content-Type': 'application/json',
        },
      );
    } catch (e) {
      debugPrint("FCM subscribe topic web failed: $e");
    }
  }

  Future<void> _unsubscribeFromTopicWeb(String token, String topic) async {
    try {
      final client = ApiClient();
      if (!await client.hasAccessToken()) return;
      final url =
          '${ApiConfig.realtimeApiBase}${PreconnectPushConfig.unsubscribeTopicPath}';
      await client.authenticatedRequest(
        'POST',
        url,
        body: jsonEncode(<String, dynamic>{'token': token, 'topic': topic}),
        additionalHeaders: const <String, String>{
          'Content-Type': 'application/json',
        },
      );
    } catch (e) {
      debugPrint("FCM unsubscribe topic web failed: $e");
    }
  }

  Future<void> subscribeToTopic(String topic) async {
    if (!isSupported) return;
    if (kIsWeb) {
      final token = await _getToken();
      if (token == null) return;
      await _subscribeToTopicWeb(token, topic);
      return;
    }
    if ((defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS) &&
        !_apnsAvailable) {
      debugPrint(
        "FCM warning: Skipping subscribeToTopic($topic) because APNS is unavailable.",
      );
      return;
    }
    await FirebaseMessaging.instance.subscribeToTopic(topic);
  }

  Future<void> unsubscribeFromTopic(String topic) async {
    if (!isSupported) return;
    if (kIsWeb) {
      final token = await _getToken();
      if (token == null) return;
      await _unsubscribeFromTopicWeb(token, topic);
      return;
    }
    if ((defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS) &&
        !_apnsAvailable) {
      debugPrint(
        "FCM warning: Skipping unsubscribeFromTopic($topic) because APNS is unavailable.",
      );
      return;
    }
    await FirebaseMessaging.instance.unsubscribeFromTopic(topic);
  }

  Future<void> init() async {
    if (!isSupported) return;
    if (!kIsWeb) {
      await _setupLocalNotifications();
    }

    RefreshBus.instance.addListener(() {
      if (RefreshBus.instance.reason == 'auth') {
        _syncToken();
      }
    });

    await _syncToken();

    if (kIsWeb) {
      await _initWeb();
      return;
    }

    await _initNative();
  }

  Future<void> _initWeb() async {
    final token = await _getToken();
    if (token == null) {
      debugPrint("Failed to get FCM token for web");
      return;
    }

    for (final topic in PreconnectPushConfig.defaultTopics) {
      await _subscribeToTopicWeb(token, topic);
    }

    try {
      Set<String> pinnedSeats = await CoursePinStore.load(
        PreconnectPushConfig.seatStatusPinScope,
      );
      for (String seat in pinnedSeats) {
        await _subscribeToTopicWeb(token, PreconnectPushConfig.seatTopic(seat));
      }
    } catch (e) {
      debugPrint("Failed to load pinned seats: $e");
    }
  }

  Future<void> _subscribeToDefaultTopics() async {
    try {
      for (final topic in PreconnectPushConfig.defaultTopics) {
        await subscribeToTopic(topic);
      }

      Set<String> pinnedSeats = await CoursePinStore.load(
        PreconnectPushConfig.seatStatusPinScope,
      );
      for (String seat in pinnedSeats) {
        await subscribeToTopic(PreconnectPushConfig.seatTopic(seat));
      }
    } catch (e) {
      debugPrint("Failed to subscribe to topics: $e");
    }
  }

  Future<void> _initNative() async {
    final messaging = FirebaseMessaging.instance;

    final settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus != AuthorizationStatus.authorized) {
      debugPrint("Notification permissions denied");
      return;
    }
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint("Foreground message: ${message.notification?.title}");
      _showLocalNotification(message);
    });

    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageTap);
    FirebaseMessaging.instance.getInitialMessage().then((message) {
      if (message != null) {
        _handleMessageTap(message);
      }
    });

    messaging.onTokenRefresh.listen((token) async {
      debugPrint("FCM token refreshed: $token");
      final wasUnavailable = !_apnsAvailable;
      _apnsAvailable = true;
      await _sendTokenToBackend(token);
      if (wasUnavailable) {
        await _subscribeToDefaultTopics();
      }
    });

    await _subscribeToDefaultTopics();
  }

  Future<void> _setupLocalNotifications() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('ic_launcher');

    const DarwinInitializationSettings initializationSettingsDarwin =
        DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        );

    const LinuxInitializationSettings initializationSettingsLinux =
        LinuxInitializationSettings(defaultActionName: 'Open notification');

    const InitializationSettings initializationSettings =
        InitializationSettings(
          android: initializationSettingsAndroid,
          iOS: initializationSettingsDarwin,
          macOS: initializationSettingsDarwin,
          linux: initializationSettingsLinux,
        );

    await _localNotifications.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        final payload = response.payload;
        if (payload != null && payload.isNotEmpty) {
          try {
            final Map<String, dynamic> data =
                jsonDecode(payload) as Map<String, dynamic>;
            var url = data['url'] as String?;
            if ((url == null || url.isEmpty) && data['courseCode'] != null) {
              url = '${ApiConfig.websiteBase}/student/advising/seat-status';
            }
            if (url != null && url.isNotEmpty) {
              try {
                final uri = Uri.parse(url);
                launchUrl(uri, mode: LaunchMode.externalApplication);
              } catch (_) {}
            }
          } catch (_) {}
        }
      },
    );

    if (defaultTargetPlatform == TargetPlatform.android) {
      const AndroidNotificationChannel channel = AndroidNotificationChannel(
        'high_importance_channel',
        'High Importance Notifications',
        description: 'This channel is used for important notifications.',
        importance: Importance.max,
      );

      await _localNotifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(channel);

      await _localNotifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      await _localNotifications
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    } else if (defaultTargetPlatform == TargetPlatform.macOS) {
      await _localNotifications
          .resolvePlatformSpecificImplementation<
            MacOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    }
  }

  void _showLocalNotification(RemoteMessage message) {
    final notification = message.notification;
    if (notification != null) {
      _localNotifications.show(
        id: notification.hashCode & 0x7FFFFFFF,
        title: notification.title,
        body: notification.body,
        payload: jsonEncode(message.data),
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'high_importance_channel',
            'High Importance Notifications',
            importance: Importance.max,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
          macOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
      );
    }
  }

  void _handleMessageTap(RemoteMessage message) {
    var url = message.data['url'] as String?;
    if ((url == null || url.isEmpty) && message.data['courseCode'] != null) {
      url = '${ApiConfig.websiteBase}/student/advising/seat-status';
    }
    if (url != null && url.isNotEmpty) {
      try {
        final uri = Uri.parse(url);
        launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {}
    }
  }

  Future<void> sendConfirmationNotification(
    String courseCode,
    String sectionName,
  ) async {
    if (!isSupported) return;
    try {
      final token = await _getToken();
      if (token == null) {
        if (kDebugMode) {
          _showLocalNotification(
            RemoteMessage(
              notification: RemoteNotification(
                title: "Seat Alerts Enabled",
                body:
                    "You'll be notified when a seat becomes available in $courseCode Section $sectionName.",
              ),
              data: <String, dynamic>{
                'url': '${ApiConfig.websiteBase}/student/advising/seat-status',
              },
            ),
          );
        }
        return;
      }
      final client = ApiClient();
      if (!await client.hasAccessToken()) return;
      final url =
          '${ApiConfig.realtimeApiBase}${PreconnectPushConfig.sendConfirmationPath}';
      await client.authenticatedRequest(
        'POST',
        url,
        body: jsonEncode(<String, dynamic>{
          'token': token,
          'courseCode': courseCode,
          'sectionName': sectionName,
        }),
        additionalHeaders: const <String, String>{
          'Content-Type': 'application/json',
        },
      );
    } catch (e) {
      debugPrint("FCM confirmation push failed: $e");
    }
  }
}
