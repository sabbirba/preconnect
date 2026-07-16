import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:preconnect/tools/app_paths.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:preconnect/firebase_options.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:preconnect/api/api_client.dart';
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/api/auth.dart';
import 'package:preconnect/api/profile.dart';
import 'package:http/http.dart' as http;
import 'package:preconnect/app.dart';
import 'package:preconnect/pages/captive_wifi.dart';
import 'package:preconnect/tools/app_storage.dart';
import 'package:preconnect/tools/preconnect_constants.dart';
import 'package:preconnect/tools/refresh_bus.dart';
import 'package:preconnect/tools/token_storage.dart';
import 'package:preconnect/tools/push_stub.dart'
    if (dart.library.js_interop) 'package:preconnect/tools/push_web.dart';
import 'package:preconnect/tools/runtime_stub.dart'
    if (dart.library.js_interop) 'package:preconnect/tools/runtime_web.dart';
import 'package:url_launcher/url_launcher.dart';

class FCMService {
  FCMService._internal();
  static final FCMService _instance = FCMService._internal();
  factory FCMService() => _instance;
  static FCMService get instance => _instance;

  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  static String? _cachedToken;
  static bool _apnsAvailable = true;

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
    await AppStorage.initialize();
    await MyApp.warmStartupCachesAsync(forceRefresh: true);
    _handleIncomingMessage(message);
  }

  static void _handleIncomingMessage(RemoteMessage message) {
    if (message.data['type'] == 'libsync_refresh') {
      final date = message.data['date'];
      final library = message.data['library'];
      if (date != null && library != null) {
        for (int cap = 1; cap <= 9; cap++) {
          final key = 'libsync_space_avail_${library}_${cap}_$date';
          AppStorage.instance.remove(key);
        }
      }
      RefreshBus.instance.notify(reason: 'libsync_refresh');
      return;
    }
    RefreshBus.instance.notify(reason: 'push_notification');
  }

  Future<String?> _getToken({bool force = false}) async {
    if (!force && _cachedToken != null) {
      return _cachedToken;
    }
    if (!kIsWeb) {
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        final status = await Permission.notification.status;
        if (!status.isGranted && !status.isLimited) {
          return null;
        }
      } else if (defaultTargetPlatform == TargetPlatform.android) {
        try {
          final androidInfo = await DeviceInfoPlugin().androidInfo;
          if (androidInfo.version.sdkInt >= 33) {
            final status = await Permission.notification.status;
            if (!status.isGranted) {
              return null;
            }
          }
        } catch (_) {}
      }
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
    } catch (_) {}
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
    } catch (_) {}
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
    } catch (_) {}
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
    } catch (_) {}
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
    } catch (_) {}
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
    } catch (_) {}
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
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    } catch (_) {}
    if (!kIsWeb) {
      await _setupLocalNotifications();
    }

    RefreshBus.instance.stream.listen((reason) {
      if (reason == 'auth') {
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
      final Set<String> pinnedSeats = await CoursePinStore.load(
        PreConnectPushConfig.seatStatusPinScope,
      );
      for (String seat in pinnedSeats) {
        await _subscribeToTopicWeb(token, PreConnectPushConfig.seatTopic(seat));
      }
    } catch (_) {}

    if (!isChromeRuntimeAvailable()) {
      try {
        FirebaseMessaging.onMessage.listen((RemoteMessage message) {
          _handleIncomingMessage(message);
        });
      } catch (_) {}
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
    } catch (_) {}
  }

  Future<void> _initNative() async {
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      if (message.data['type'] == 'libsync_refresh') {
        _handleIncomingMessage(message);
        return;
      }
      _showLocalNotification(message);
      RefreshBus.instance.notify(reason: 'push_notification');
    });

    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageTap);
    FirebaseMessaging.instance.getInitialMessage().then((message) {
      if (message != null) {
        _handleMessageTap(message);
      }
    });

    FirebaseMessaging.instance.onTokenRefresh.listen((token) async {
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
          if (payload == 'captive_wifi') {
            AuthService.navigatorKey.currentState?.push(
              MaterialPageRoute(builder: (context) => const CaptiveWifiPage()),
            );
            return;
          }
          try {
            final Map<String, dynamic> data =
                jsonDecode(payload) as Map<String, dynamic>;
            _handleNotificationTapAction(data);
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

  Future<void> showLocalNotificationDirect({
    required String title,
    required String body,
    String? imageUrl,
    Map<String, dynamic> data = const {},
  }) async {
    if (kIsWeb) return;
    StyleInformation? styleInformation;
    List<DarwinNotificationAttachment>? darwinAttachments;
    if (imageUrl != null && imageUrl.isNotEmpty) {
      try {
        final response = await http
            .get(Uri.parse(imageUrl))
            .timeout(const Duration(seconds: 5));
        if (response.statusCode == 200) {
          if (defaultTargetPlatform == TargetPlatform.android) {
            styleInformation = BigPictureStyleInformation(
              ByteArrayAndroidBitmap(response.bodyBytes),
              hideExpandedLargeIcon: true,
            );
          } else if (defaultTargetPlatform == TargetPlatform.iOS ||
              defaultTargetPlatform == TargetPlatform.macOS) {
            final tempDir = await AppPaths.temporaryDirectory();
            final tempFile = File('${tempDir.path}/${imageUrl.hashCode}.png');
            await tempFile.writeAsBytes(response.bodyBytes);
            darwinAttachments = [DarwinNotificationAttachment(tempFile.path)];
          }
        }
      } catch (_) {}
    }
    await _localNotifications.show(
      id: (title.hashCode ^ body.hashCode) & 0x7FFFFFFF,
      title: title,
      body: body,
      payload: jsonEncode(data),
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          'high_importance_channel',
          'High Importance Notifications',
          importance: Importance.max,
          priority: Priority.high,
          icon: 'ic_stat_preconnect',
          styleInformation: styleInformation,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          attachments: darwinAttachments,
        ),
        macOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          attachments: darwinAttachments,
        ),
      ),
    );
  }

  void _handleMessageTap(RemoteMessage message) {
    _handleNotificationTapAction(message.data);
  }

  void _handleNotificationTapAction(Map<String, dynamic> data) {
    final action = data['payload'] ?? data['action'];
    if (action == 'captive_wifi') {
      AuthService.navigatorKey.currentState?.push(
        MaterialPageRoute(builder: (context) => const CaptiveWifiPage()),
      );
      return;
    }
    var url = data['url'] as String?;
    if ((url == null || url.isEmpty) && data['courseCode'] != null) {
      final courseCode = '${data['courseCode'] ?? ''}'.trim();
      final sectionName = '${data['sectionName'] ?? ''}'.trim();
      final facultyName = '${data['facultyName'] ?? ''}'.trim();
      if (courseCode.isNotEmpty) {
        var query = courseCode;
        if (sectionName.isNotEmpty) {
          query += ' $sectionName';
          if (facultyName.isNotEmpty) {
            query += ' $facultyName';
          }
        }
        final formattedQuery = query.replaceAll(' ', '+');
        url = '${ApiConfig.websiteBase}/seat?course=$formattedQuery';
      } else {
        url = '${ApiConfig.websiteBase}/student/advising/seat-status';
      }
    }
    if (url != null && url.isNotEmpty) {
      try {
        final uri = Uri.parse(url);
        unawaited(launchUrl(uri, mode: LaunchMode.inAppWebView));
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
    } catch (_) {}
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
