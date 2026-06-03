import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:preconnect/api/api_client.dart';
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/tools/refresh_bus.dart';
import 'package:preconnect/tools/token_storage.dart';
import 'package:url_launcher/url_launcher.dart';

class FCMService {
  FCMService._();

  static final FCMService instance = FCMService._();
  static final String _pinScope = "seat_status";
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  bool _apnsAvailable = true;

  static Future<void> _backgroundHandler(RemoteMessage message) async {
    await Firebase.initializeApp();
    debugPrint("Background message: ${message.messageId}");
  }

  Future<String?> _getToken() async {
    if (kIsWeb) {
      final token = await TokenStorage.instance.read(key: 'preconnect.gcmToken');
      debugPrint("FCM Web Token: $token");
      return token;
    }
    try {
      if (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS) {
        String? apnsToken;
        int retries = 0;
        final maxRetries = (defaultTargetPlatform == TargetPlatform.macOS && kDebugMode) ? 1 : 10;

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
          debugPrint("FCM Error: Failed to get APNS token after retries. Push notifications will not work.");
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
      final url = '${ApiConfig.realtimeApiBase}/push/device/register';
      await client.authenticatedRequest(
        'POST',
        url,
        body: jsonEncode(<String, dynamic>{
          'token': token,
          'platform': kIsWeb
              ? 'chrome_extension'
              : defaultTargetPlatform.name.toLowerCase(),
        }),
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
      final url = '${ApiConfig.realtimeApiBase}/push/topic/subscribe';
      await client.authenticatedRequest(
        'POST',
        url,
        body: jsonEncode(<String, dynamic>{'token': token, 'topic': topic}),
      );
    } catch (e) {
      debugPrint("FCM subscribe topic web failed: $e");
    }
  }

  Future<void> _unsubscribeFromTopicWeb(String token, String topic) async {
    try {
      final client = ApiClient();
      if (!await client.hasAccessToken()) return;
      final url = '${ApiConfig.realtimeApiBase}/push/topic/unsubscribe';
      await client.authenticatedRequest(
        'POST',
        url,
        body: jsonEncode(<String, dynamic>{'token': token, 'topic': topic}),
      );
    } catch (e) {
      debugPrint("FCM unsubscribe topic web failed: $e");
    }
  }

  Future<void> subscribeToTopic(String topic) async {
    if (kIsWeb) {
      final token = await _getToken();
      if (token == null) return;
      await _subscribeToTopicWeb(token, topic);
      return;
    }
    if ((defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS) &&
        !_apnsAvailable) {
      debugPrint("FCM warning: Skipping subscribeToTopic($topic) because APNS is unavailable.");
      return;
    }
    await FirebaseMessaging.instance.subscribeToTopic(topic);
  }

  Future<void> unsubscribeFromTopic(String topic) async {
    if (kIsWeb) {
      final token = await _getToken();
      if (token == null) return;
      await _unsubscribeFromTopicWeb(token, topic);
      return;
    }
    if ((defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS) &&
        !_apnsAvailable) {
      debugPrint("FCM warning: Skipping unsubscribeFromTopic($topic) because APNS is unavailable.");
      return;
    }
    await FirebaseMessaging.instance.unsubscribeFromTopic(topic);
  }

  Future<void> init() async {
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

    await _subscribeToTopicWeb(token, "announcements");
    await _subscribeToTopicWeb(token, "news");

    try {
      Set<String> pinnedSeats = await CoursePinStore.load(_pinScope);
      for (String seat in pinnedSeats) {
        await _subscribeToTopicWeb(token, "seat_$seat");
      }
    } catch (e) {
      debugPrint("Failed to load pinned seats: $e");
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

    FirebaseMessaging.onBackgroundMessage(_backgroundHandler);

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
      await _sendTokenToBackend(token);
    });

    try {
      if ((defaultTargetPlatform != TargetPlatform.iOS &&
              defaultTargetPlatform != TargetPlatform.macOS) ||
          _apnsAvailable) {
        await messaging.subscribeToTopic("announcements");
        await messaging.subscribeToTopic("news");

        Set<String> pinnedSeats = await CoursePinStore.load(_pinScope);
        for (String seat in pinnedSeats) {
          await messaging.subscribeToTopic("seat_$seat");
        }
      } else {
        debugPrint("FCM warning: Skipping startup topic subscriptions because APNS is unavailable.");
      }
    } catch (e) {
      debugPrint("Failed to subscribe to topics: $e");
    }
  }

  Future<void> _setupLocalNotifications() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings initializationSettingsDarwin =
        DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const LinuxInitializationSettings initializationSettingsLinux =
        LinuxInitializationSettings(
      defaultActionName: 'Open notification',
    );

    const InitializationSettings initializationSettings = InitializationSettings(
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
            final url = data['url'] as String?;
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
          ?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          );
    } else if (defaultTargetPlatform == TargetPlatform.macOS) {
      await _localNotifications
          .resolvePlatformSpecificImplementation<
              MacOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          );
    }
  }

  void _showLocalNotification(RemoteMessage message) {
    final notification = message.notification;
    if (notification != null) {
      _localNotifications.show(
        id: notification.hashCode,
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
    final url = message.data['url'] as String?;
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
    try {
      final token = await _getToken();
      if (token == null) {
        if (kDebugMode) {
          _showLocalNotification(RemoteMessage(
            notification: RemoteNotification(
              title: "Seat Alerts Enabled",
              body: "You will be notified immediately when a seat becomes available in $courseCode Section $sectionName.",
            ),
            data: <String, dynamic>{
              'url': '${ApiConfig.websiteBase}/student/advising/seat-status',
            },
          ));
        }
        return;
      }
      final client = ApiClient();
      if (!await client.hasAccessToken()) return;
      final url = '${ApiConfig.realtimeApiBase}/push/device/send-confirmation';
      await client.authenticatedRequest(
        'POST',
        url,
        body: jsonEncode(<String, dynamic>{
          'token': token,
          'courseCode': courseCode,
          'sectionName': sectionName,
        }),
      );
    } catch (e) {
      debugPrint("FCM confirmation push failed: $e");
    }
  }
}
