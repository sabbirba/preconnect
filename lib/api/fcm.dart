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
  String? _cachedToken;

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
  }

  Future<String?> _getToken({bool force = false}) async {
    if (!force && _cachedToken != null) {
      return _cachedToken;
    }
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

        _cachedToken = token;
        return token;
      } else {
        try {
          final token = await FirebaseMessaging.instance.getToken();

          _cachedToken = token;
          return token;
        } catch (e) {
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

          if (apnsToken == null) {
            await Future.delayed(const Duration(seconds: 1));
            retries++;
          }
        }

        if (apnsToken == null) {
          _apnsAvailable = false;

          return null;
        } else {
          _apnsAvailable = true;
        }
      }
      final token = await FirebaseMessaging.instance.getToken();

      _cachedToken = token;
      return token;
    } catch (e) {
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
    } catch (_) {
      assert(true);
    }
  }

  Future<void> _syncToken() async {
    final token = await _getToken();

    if (token != null) {
      unawaited(_sendTokenToBackend(token));
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
    } catch (_) {
      assert(true);
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
    } catch (_) {
      assert(true);
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
        return false;
      }
      return true;
    } catch (e) {
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
      return false;
    }
  }

  Future<bool> subscribeToTopic(String topic) async {
    if (!isSupported) return false;
    final token = await _getToken();
    return _subscribeToTopicInternal(topic, cachedToken: token);
  }

  Future<bool> _subscribeToTopicInternal(
    String topic, {
    String? cachedToken,
  }) async {
    if (!isSupported) return false;

    final token = cachedToken ?? await _getToken();

    if (kIsWeb) {
      if (token == null) return false;
      await _subscribeToTopicWeb(token, topic);
      return true;
    }
    if ((defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS) &&
        !_apnsAvailable) {
      return true;
    }

    if (token != null) {
      unawaited(_subscribeToTopicWeb(token, topic));
    }

    try {
      await FirebaseMessaging.instance.subscribeToTopic(topic);
    } catch (_) {
      assert(true);
    }
    return true;
  }

  Future<bool> unsubscribeFromTopic(String topic) async {
    if (!isSupported) return false;
    final token = await _getToken();
    return _unsubscribeFromTopicInternal(topic, cachedToken: token);
  }

  Future<bool> _unsubscribeFromTopicInternal(
    String topic, {
    String? cachedToken,
  }) async {
    if (!isSupported) return false;

    final token = cachedToken ?? await _getToken();

    if (kIsWeb) {
      if (token == null) return false;
      await _unsubscribeFromTopicWeb(token, topic);
      return true;
    }
    if ((defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS) &&
        !_apnsAvailable) {
      return true;
    }

    if (token != null) {
      unawaited(_unsubscribeFromTopicWeb(token, topic));
    }
    try {
      await FirebaseMessaging.instance.unsubscribeFromTopic(topic);
    } catch (_) {
      assert(true);
    }
    return true;
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
    } catch (_) {
      assert(true);
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

        return granted;
      } catch (e) {
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

      return granted;
    } catch (e) {
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
      return false;
    }
  }

  Future<void> init() async {
    if (!isSupported) return;
    if (!kIsWeb) {
      await _setupLocalNotifications();
    }

    RefreshBus.instance.tick.subscribe((_) {
      if (RefreshBus.instance.reason.value == 'auth') {
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
    } catch (_) {
      assert(true);
    }

    if (!isChromeRuntimeAvailable()) {
      try {
        FirebaseMessaging.onMessage.listen((RemoteMessage message) {
          RefreshBus.instance.notify(reason: 'push_notification');
        });
      } catch (_) {
        assert(true);
      }
    }
  }

  Future<void> _subscribeToDefaultTopics() async {
    final token = await _getToken();
    try {
      for (final topic in PreConnectPushConfig.defaultTopics) {
        await _subscribeToTopicInternal(topic, cachedToken: token);
      }

      final Set<String> pinnedSeats = await CoursePinStore.load(
        PreConnectPushConfig.seatStatusPinScope,
      );
      for (final String seat in pinnedSeats) {
        await _subscribeToTopicInternal(
          PreConnectPushConfig.seatTopic(seat),
          cachedToken: token,
        );
      }
    } catch (_) {
      assert(true);
    }
  }

  Future<void> _initNative() async {
    final messaging = FirebaseMessaging.instance;

    try {
      await messaging.requestPermission(alert: true, badge: true, sound: true);
    } catch (_) {
      assert(true);
    }

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      _showLocalNotification(message);
      RefreshBus.instance.notify(reason: 'push_notification');
    });

    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageTap);
    FirebaseMessaging.instance.getInitialMessage().then((message) {
      if (message != null) {
        _handleMessageTap(message);
      }
    });

    messaging.onTokenRefresh.listen((token) async {
      final wasUnavailable = !_apnsAvailable;
      _apnsAvailable = true;
      await _sendTokenToBackend(token);
      if (wasUnavailable) {
        await _subscribeToDefaultTopics();
      }
    });

    if (defaultTargetPlatform == TargetPlatform.android) {
      await Future<void>.delayed(const Duration(seconds: 3));
    }
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
              } catch (_) {
                assert(true);
              }
            }
          } catch (_) {
            assert(true);
          }
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
      } catch (_) {
        assert(true);
      }
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
      unawaited(
        client.authenticatedRequest(
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
        ),
      );
    } catch (_) {
      assert(true);
    }
  }

  Future<void> showNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    if (kIsWeb) return;
    await _localNotifications.show(
      id: id,
      title: title,
      body: body,
      payload: payload,
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
      ),
    );
  }
}
