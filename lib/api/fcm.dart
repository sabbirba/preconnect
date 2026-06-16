import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:preconnect/api/api_client.dart';
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/api/profile.dart';
import 'package:http/http.dart' as http;
import 'package:preconnect/tools/preconnect_constants.dart';
import 'package:preconnect/tools/refresh_bus.dart';
import 'package:preconnect/tools/token_storage.dart';
import 'package:preconnect/tools/push_stub.dart'
    if (dart.library.html) 'package:preconnect/tools/push_web.dart';
import 'package:preconnect/tools/runtime_stub.dart'
    if (dart.library.html) 'package:preconnect/tools/runtime_web.dart';
import 'package:url_launcher/url_launcher.dart';

class FCMService {
  FCMService._();

  static final FCMService instance = FCMService._();
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  bool _apnsAvailable = true;

  bool get isSupported {
    if (kIsWeb) {
      return true;
    }
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;
  }

  @pragma('vm:entry-point')
  static Future<void> backgroundHandler(RemoteMessage message) async {
    await Firebase.initializeApp();
    debugPrint("Background message: ${message.messageId}");
  }

  Future<String?> _getToken() async {
    if (kIsWeb) {
      if (isChromeRuntimeAvailable()) {
        var token = await TokenStorage.instance.read(
          key: PreConnectPushConfig.gcmTokenKey,
        );
        if (token == null || token.isEmpty) {
          await requestWebExtensionPushTokenSync();
          for (var attempt = 0; attempt < 5; attempt++) {
            await Future<void>.delayed(const Duration(milliseconds: 200));
            token = await TokenStorage.instance.read(
              key: PreConnectPushConfig.gcmTokenKey,
            );
            if (token != null && token.isNotEmpty) break;
          }
        }
        debugPrint("FCM Chrome Extension Token: $token");
        return token;
      } else {
        try {
          final token = await FirebaseMessaging.instance.getToken();
          debugPrint("FCM Standard Web Token: $token");
          return token;
        } catch (e) {
          debugPrint("FCM Standard Web token fetch error: $e");
          return null;
        }
      }
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
          '${ApiConfig.realtimeApiBase}${PreConnectPushConfig.registerDevicePath}';
      await client.authenticatedRequest(
        'POST',
        url,
        body: jsonEncode(<String, dynamic>{
          'token': token,
          'platform': kIsWeb
              ? (isChromeRuntimeAvailable()
                    ? PreConnectPushConfig.chromeExtensionPlatform
                    : 'web')
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
          '${ApiConfig.realtimeApiBase}${PreConnectPushConfig.subscribeTopicPath}';
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
          '${ApiConfig.realtimeApiBase}${PreConnectPushConfig.unsubscribeTopicPath}';
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

  Future<bool> syncSeatEmailAlert(
    String courseCode,
    String sectionName, {
    required bool subscribe,
  }) async {
    try {
      final profile = await ProfileService().getProfile();
      final email =
          profile?['institutionalEmail'] ??
          profile?['email'] ??
          profile?['studentEmail'];
      if (email == null || email.isEmpty) return true;

      final url = subscribe
          ? '${ApiConfig.websiteBase}/api/_client/seat-watch/register'
          : '${ApiConfig.websiteBase}/api/_client/seat-watch/unregister';

      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'courseCode': courseCode,
          'sectionName': sectionName,
          'provider': 'email',
          'endpoint': 'email:$email',
        }),
      );

      if (response.statusCode != 200) {
        debugPrint(
          'Seat email sync failed: ${response.statusCode} ${response.body}',
        );
        return false;
      }
      return true;
    } catch (e) {
      debugPrint('Seat email sync error: $e');
      return false;
    }
  }

  Future<bool> syncWatchlistSnapshot(
    String courseCode,
    String sectionName, {
    required bool subscribe,
  }) async {
    try {
      final idToken = await TokenStorage.instance.read(
        key: PreConnectStorageKeys.idToken,
      );
      if (idToken == null || idToken.isEmpty) return false;

      final loadUrl = '${ApiConfig.websiteBase}/api/_client/load-snapshot';
      final client = ApiClient();
      final loadRes = await client.publicPost(
        loadUrl,
        body: jsonEncode(<String, dynamic>{
          'idToken': idToken,
          'key': 'seat.watchlist',
        }),
      );

      List<dynamic> currentList = <dynamic>[];
      if (loadRes.statusCode == 200) {
        final map = jsonDecode(loadRes.body) as Map<String, dynamic>;
        final found = map['found'] as bool? ?? false;
        if (found && map['data'] is List) {
          currentList = List<dynamic>.from(map['data'] as List);
        }
      }

      String normCourse(String code) => code.trim().toUpperCase();
      String normSection(String sec) {
        final raw = sec.trim();
        if (raw.isEmpty) return '';
        final parsed = int.tryParse(raw);
        if (parsed != null) return parsed.toString();
        return raw.toUpperCase();
      }

      final targetCourse = normCourse(courseCode);
      final targetSection = normSection(sectionName);

      if (subscribe) {
        bool exists = false;
        for (final item in currentList) {
          if (item is Map) {
            final c = normCourse(item['courseCode']?.toString() ?? '');
            final s = normSection(item['sectionName']?.toString() ?? '');
            if (c == targetCourse && s == targetSection) {
              exists = true;
              break;
            }
          }
        }
        if (!exists) {
          currentList.add(<String, dynamic>{
            'courseCode': targetCourse,
            'sectionName': targetSection,
            'addedAt': DateTime.now().millisecondsSinceEpoch,
          });
        }
      } else {
        currentList.removeWhere((dynamic item) {
          if (item is! Map) return false;
          final c = normCourse(item['courseCode']?.toString() ?? '');
          final s = normSection(item['sectionName']?.toString() ?? '');
          return c == targetCourse && s == targetSection;
        });
      }

      final saveUrl = '${ApiConfig.websiteBase}/api/_client/save-snapshot';
      final saveRes = await client.publicPost(
        saveUrl,
        body: jsonEncode(<String, dynamic>{
          'idToken': idToken,
          'key': 'seat.watchlist',
          'data': currentList,
        }),
      );

      return saveRes.statusCode == 200;
    } catch (e) {
      debugPrint('Watchlist snapshot sync error: $e');
      return false;
    }
  }

  Future<bool> subscribeToTopic(String topic) async {
    if (!isSupported) return false;

    if (kIsWeb) {
      final token = await _getToken();
      if (token == null) return false;
      await _subscribeToTopicWeb(token, topic);
      return true;
    }
    if ((defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS) &&
        !_apnsAvailable) {
      return true;
    }
    try {
      await FirebaseMessaging.instance.subscribeToTopic(topic);
      return true;
    } catch (e) {
      debugPrint("FCM error subscribing to topic $topic: $e");
      return false;
    }
  }

  Future<bool> unsubscribeFromTopic(String topic) async {
    if (!isSupported) return false;

    if (kIsWeb) {
      final token = await _getToken();
      if (token == null) return false;
      await _unsubscribeFromTopicWeb(token, topic);
      return true;
    }
    if ((defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS) &&
        !_apnsAvailable) {
      return true;
    }
    try {
      await FirebaseMessaging.instance.unsubscribeFromTopic(topic);
      return true;
    } catch (e) {
      debugPrint("FCM error unsubscribing from topic $topic: $e");
      return false;
    }
  }

  Future<void> unregisterDevice() async {
    if (!isSupported) return;
    try {
      final token = await _getToken();
      if (token == null) return;
      final client = ApiClient();
      if (!await client.hasAccessToken()) return;
      final url =
          '${ApiConfig.realtimeApiBase}${PreConnectPushConfig.unregisterDevicePath}';
      await client.authenticatedRequest(
        'POST',
        url,
        body: jsonEncode(<String, dynamic>{'token': token}),
        additionalHeaders: const <String, String>{
          'Content-Type': 'application/json',
        },
      );
    } catch (e) {
      debugPrint("FCM device unregister failed: $e");
    }
  }

  Future<bool> requestNotificationPermission() async {
    if (!isSupported) return false;

    if (kIsWeb && isChromeRuntimeAvailable()) return true;

    if (kIsWeb) {
      try {
        final messaging = FirebaseMessaging.instance;
        final settings = await messaging.requestPermission(
          alert: true,
          badge: true,
          sound: true,
        );
        final granted =
            settings.authorizationStatus == AuthorizationStatus.authorized;
        debugPrint("Notification permission request result (web): $granted");
        return granted;
      } catch (e) {
        debugPrint("Error requesting notification permission (web): $e");
        return false;
      }
    }

    try {
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if (defaultTargetPlatform == TargetPlatform.android) {
        await _localNotifications
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.requestNotificationsPermission();
      }

      final granted =
          settings.authorizationStatus == AuthorizationStatus.authorized;
      debugPrint("Notification permission request result: $granted");
      return granted;
    } catch (e) {
      debugPrint("Error requesting notification permission: $e");
      return false;
    }
  }

  Future<bool> isNotificationPermissionGranted() async {
    if (!isSupported) return false;

    if (kIsWeb && isChromeRuntimeAvailable()) return true;

    try {
      final settings = await FirebaseMessaging.instance
          .getNotificationSettings();
      return settings.authorizationStatus == AuthorizationStatus.authorized;
    } catch (e) {
      debugPrint("Error checking notification settings: $e");
      return false;
    }
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

    for (final topic in PreConnectPushConfig.defaultTopics) {
      await _subscribeToTopicWeb(token, topic);
    }

    try {
      Set<String> pinnedSeats = await CoursePinStore.load(
        PreConnectPushConfig.seatStatusPinScope,
      );
      for (String seat in pinnedSeats) {
        await _subscribeToTopicWeb(token, PreConnectPushConfig.seatTopic(seat));
      }
    } catch (e) {
      debugPrint("Failed to load pinned seats: $e");
    }

    if (!isChromeRuntimeAvailable()) {
      try {
        FirebaseMessaging.onMessage.listen((RemoteMessage message) {
          debugPrint(
            "Standard Web foreground message: ${message.notification?.title}",
          );
        });
      } catch (e) {
        debugPrint("Error registering standard web foreground listener: $e");
      }
    }
  }

  Future<void> _subscribeToDefaultTopics() async {
    try {
      for (final topic in PreConnectPushConfig.defaultTopics) {
        await subscribeToTopic(topic);
      }

      Set<String> pinnedSeats = await CoursePinStore.load(
        PreConnectPushConfig.seatStatusPinScope,
      );
      for (String seat in pinnedSeats) {
        await subscribeToTopic(PreConnectPushConfig.seatTopic(seat));
      }
    } catch (e) {
      debugPrint("Failed to subscribe to topics: $e");
    }
  }

  Future<void> _initNative() async {
    final messaging = FirebaseMessaging.instance;

    try {
      await messaging.requestPermission(alert: true, badge: true, sound: true);
    } catch (e) {
      debugPrint("FCM requestPermission error: $e");
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
        AndroidInitializationSettings('ic_stat_preconnect');

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
    if (kIsWeb) return;
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
            icon: 'ic_stat_preconnect',
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
        if (kDebugMode && !kIsWeb) {
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
          '${ApiConfig.realtimeApiBase}${PreConnectPushConfig.sendConfirmationPath}';
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
