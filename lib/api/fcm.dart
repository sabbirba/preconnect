import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class FCMService {
  FCMService._();

  static final FCMService instance = FCMService._();

  static Future<void> _backgroundHandler(RemoteMessage message) async {
    await Firebase.initializeApp();
    print("Background message: ${message.messageId}");
  }

  Future<void> _syncToken() async {
    final token = await FirebaseMessaging.instance.getToken();

    if (token != null) {
      print("Initial token: $token");
      // send to backend here
    }
  }

  Future<void> init() async {
    await _syncToken();

    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission();

    FirebaseMessaging.onBackgroundMessage(_backgroundHandler);

    FirebaseMessaging.onMessage.listen((message) {
      print("Foreground message: ${message.notification?.title}");
      // bg message
    });

    messaging.onTokenRefresh.listen((token) {
      print("New device token: $token");
      // token refresh
    });
  }
}
