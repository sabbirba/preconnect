import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:preconnect/tools/token_storage.dart';

class FCMService {
  FCMService._();

  static final FCMService instance = FCMService._();
  static final String _pinScope = "seat_status";

  static Future<void> _backgroundHandler(RemoteMessage message) async {
    await Firebase.initializeApp();
    debugPrint("Background message: ${message.messageId}");
  }

  Future<void> _sendTokenToBackend(String token) async {
    // complete code here
  }

  Future<void> _syncToken() async {
    final token = await FirebaseMessaging.instance.getToken();

    if (token != null) {
      await _sendTokenToBackend(token);
    }
  }

  Future<void> init() async {
    await _syncToken();

    Set<String> pinnedSeats = await CoursePinStore.load(_pinScope);

    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission();

    FirebaseMessaging.onBackgroundMessage(_backgroundHandler);

    FirebaseMessaging.onMessage.listen((message) {
      debugPrint("Foreground message: ${message.notification?.title}");
    });

    messaging.onTokenRefresh.listen((token) async {
      await _sendTokenToBackend(token);
    });

    for (String seat in pinnedSeats) {
      messaging.subscribeToTopic("seat_$seat");
    }
  }
}
