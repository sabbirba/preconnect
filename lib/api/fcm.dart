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

  static Future<void> _backgroundHandler(RemoteMessage message) async {
    await Firebase.initializeApp();
    debugPrint("Background message: ${message.messageId}");
  }

  Future<String?> _getToken() async {
    if (kIsWeb) {
      return await TokenStorage.instance.read(key: 'preconnect.gcmToken');
    }

    // iOS: Wait for APNS token to be available
    if (defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.iOS) {
      String? apnsToken;
      int retries = 0;
      const maxRetries = 10;

      while (apnsToken == null && retries < maxRetries) {
        apnsToken = await FirebaseMessaging.instance.getAPNSToken();
        if (apnsToken == null) {
          await Future.delayed(const Duration(seconds: 1));
          retries++;
        }
      }

      if (apnsToken == null) {
        debugPrint("Failed to get APNS token after retries");
        return null;
      }
    }

    return await FirebaseMessaging.instance.getToken();
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
    await FirebaseMessaging.instance.subscribeToTopic(topic);
  }

  Future<void> unsubscribeFromTopic(String topic) async {
    if (kIsWeb) {
      final token = await _getToken();
      if (token == null) return;
      await _unsubscribeFromTopicWeb(token, topic);
      return;
    }
    await FirebaseMessaging.instance.unsubscribeFromTopic(topic);
  }

  Future<void> init() async {
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

    // Subscribe to default topics
    await _subscribeToTopicWeb(token, "announcements");
    await _subscribeToTopicWeb(token, "news");

    // Subscribe to pinned seats
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

    // Request permissions
    final settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus != AuthorizationStatus.authorized) {
      debugPrint("Notification permissions denied");
      return;
    }

    // Setup local notifications for foreground messages
    await _setupLocalNotifications();

    // Background message handler
    FirebaseMessaging.onBackgroundMessage(_backgroundHandler);

    // Foreground message handler - DISPLAY THE NOTIFICATION
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint("Foreground message: ${message.notification?.title}");
      _showLocalNotification(message);
    });

    // Handle notification taps
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageTap);
    FirebaseMessaging.instance.getInitialMessage().then((message) {
      if (message != null) {
        _handleMessageTap(message);
      }
    });

    // Token refresh listener
    messaging.onTokenRefresh.listen((token) async {
      debugPrint("FCM token refreshed: $token");
      await _sendTokenToBackend(token);
    });

    // Subscribe to topics
    try {
      await messaging.subscribeToTopic("announcements");
      await messaging.subscribeToTopic("news");

      Set<String> pinnedSeats = await CoursePinStore.load(_pinScope);
      for (String seat in pinnedSeats) {
        await messaging.subscribeToTopic("seat_$seat");
      }
    } catch (e) {
      debugPrint("Failed to subscribe to topics: $e");
    }
  }

  Future<void> _setupLocalNotifications() async {
    // Create Android notification channel
    if (defaultTargetPlatform == TargetPlatform.android) {
      const AndroidNotificationChannel channel = AndroidNotificationChannel(
        'high_importance_channel',
        'High Importance Notifications',
        description: 'This channel is used for important notifications.',
        importance: Importance.max,
      );

      await FlutterLocalNotificationsPlugin()
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(channel);
    }
  }

  void _showLocalNotification(RemoteMessage message) {
    final notification = message.notification;
    if (notification != null) {
      FlutterLocalNotificationsPlugin().show(
        id: notification.hashCode,
        title: notification.title,
        body: notification.body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'high_importance_channel',
            'High Importance Notifications',
            importance: Importance.max,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
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
      if (token == null) return;
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
