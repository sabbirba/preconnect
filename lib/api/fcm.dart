import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
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
          'platform': defaultTargetPlatform.name.toLowerCase(),
        }),
      );
    } catch (e) {
      debugPrint("FCM token registration failed: $e");
    }
  }

  Future<void> _syncToken() async {
    final token = await FirebaseMessaging.instance.getToken();

    if (token != null) {
      await _sendTokenToBackend(token);
    }
  }

  Future<void> init() async {
    RefreshBus.instance.addListener(() {
      if (RefreshBus.instance.reason == 'auth') {
        _syncToken();
      }
    });

    await _syncToken();

    Set<String> pinnedSeats = await CoursePinStore.load(_pinScope);

    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    FirebaseMessaging.onBackgroundMessage(_backgroundHandler);

    FirebaseMessaging.onMessage.listen((message) {
      debugPrint("Foreground message: ${message.notification?.title}");
    });

    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageTap);
    FirebaseMessaging.instance.getInitialMessage().then((message) {
      if (message != null) {
        _handleMessageTap(message);
      }
    });

    messaging.onTokenRefresh.listen((token) async {
      await _sendTokenToBackend(token);
    });

    await messaging.subscribeToTopic("announcements");
    await messaging.subscribeToTopic("news");

    for (String seat in pinnedSeats) {
      messaging.subscribeToTopic("seat_$seat");
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

  Future<void> sendConfirmationNotification(String courseCode, String sectionName) async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
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
