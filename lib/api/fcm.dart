import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:preconnect/tools/app_paths.dart';
import 'package:preconnect/tools/app_log.dart';
import 'package:preconnect/tools/notification_text.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:preconnect/firebase_options.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/api/chat.dart';
import 'package:preconnect/api/dataset_sync.dart';
import 'package:preconnect/api/notification.dart';
import 'package:preconnect/features/notifications/data/device_registry.dart';
import 'package:preconnect/features/notifications/data/push_registration.dart';
import 'package:preconnect/tools/http/http_utils.dart';
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
  PushRegistration? _registration;
  StreamSubscription<String>? _registrationListener;
  static bool _apnsAvailable = true;
  void Function()? _openCaptiveWifi;
  Future<void> Function(String url)? _openUrl;
  void Function()? _openNotifications;
  void Function(String roomId)? _openChat;

  void configureNavigation({
    required void Function() openCaptiveWifi,
    required Future<void> Function(String url) openUrl,
    void Function()? openNotifications,
    void Function(String roomId)? openChat,
  }) {
    _openCaptiveWifi = openCaptiveWifi;
    _openUrl = openUrl;
    _openNotifications = openNotifications;
    _openChat = openChat;
  }

  static Future<void>? _firebaseReady;

  static Future<void> ensureFirebase() {
    if (isChromeRuntimeAvailable()) return Future<void>.value();
    return _firebaseReady ??= _initializeFirebase();
  }

  static Future<void> _initializeFirebase() async {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      FirebaseMessaging.onBackgroundMessage(backgroundHandler);
    } catch (error, stackTrace) {
      unawaited(
        AppLog.write('Firebase initialization failed: $error\n$stackTrace'),
      );
    }
  }

  bool get isSupported {
    if (kIsWeb) {
      return true;
    }
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;
  }

  static bool _isLocalNotifInitialized = false;

  @pragma('vm:entry-point')
  static void _onBackgroundNotificationResponse(NotificationResponse response) {
    final payload = response.payload;
    if (payload != null && payload.isNotEmpty) {
      if (payload == 'captive_wifi') {
        _instance._openCaptiveWifi?.call();
        return;
      }
      try {
        final decoded = jsonDecode(payload);
        if (decoded is Map) {
          _instance._handleNotificationTapAction(
            Map<String, dynamic>.from(decoded),
          );
        }
      } catch (error) {
        unawaited(AppLog.write('Notification payload decode failed: $error'));
      }
    }
  }

  static Future<void> ensureLocalNotificationsInitialized() async {
    if (_isLocalNotifInitialized || kIsWeb) return;
    _isLocalNotifInitialized = true;

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('status_icon');

    const DarwinInitializationSettings initializationSettingsDarwin =
        DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
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
      onDidReceiveNotificationResponse: _onBackgroundNotificationResponse,
      onDidReceiveBackgroundNotificationResponse:
          _onBackgroundNotificationResponse,
    );

    final launchDetails = await _localNotifications
        .getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp ?? false) {
      final response = launchDetails?.notificationResponse;
      if (response != null &&
          response.payload != null &&
          response.payload!.isNotEmpty) {
        if (response.payload == 'captive_wifi') {
          _instance._openCaptiveWifi?.call();
        } else {
          try {
            final decoded = jsonDecode(response.payload!);
            if (decoded is Map) {
              _instance._handleNotificationTapAction(
                Map<String, dynamic>.from(decoded),
              );
            }
          } catch (error) {
            unawaited(
              AppLog.write('Notification launch payload decode failed: $error'),
            );
          }
        }
      }
    }

    if (defaultTargetPlatform == TargetPlatform.android) {
      const AndroidNotificationChannel channel = AndroidNotificationChannel(
        'high_importance_channel',
        'High Importance Notifications',
        description: 'This channel is used for important notifications.',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        showBadge: true,
      );

      final androidPlugin = _localNotifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await androidPlugin?.createNotificationChannel(channel);
      await androidPlugin?.requestNotificationsPermission();
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

  @pragma('vm:entry-point')
  static Future<void> backgroundHandler(RemoteMessage message) async {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    await AppStorage.initialize();
    await ensureLocalNotificationsInitialized();
    if (message.notification == null) {
      await _handleIncomingMessage(message);
    } else {
      RefreshBus.instance.notify(reason: 'push_notification');
      await DatasetSync.instance.applyPush(message.data);
    }
    unawaited(NotificationService().getFeedItems(forceRefresh: true));
    unawaited(NotificationService().fetchRecentNotifications());
  }

  static String cleanNotificationDescription(
    String rawBody, {
    String? category,
    String? module,
    String? source,
  }) => stripNotificationCategory(
    rawBody,
    categories: [category, module, source],
  );

  static String _notificationCategory(Map<String, dynamic> data) =>
      (data['category'] ?? data['module'] ?? data['source'] ?? '')
          .toString()
          .trim();

  static String _firstClean(List<Object?> values, String category) {
    for (final value in values) {
      final cleaned = cleanNotificationDescription(
        '${value ?? ''}'.trim(),
        category: category,
      );
      if (cleaned.isNotEmpty) return cleaned;
    }
    return '';
  }

  static (String, String) _resolveNotificationTitleAndBody(
    RemoteNotification? notification,
    Map<String, dynamic> data,
  ) {
    final category = _notificationCategory(data);
    final title = _firstClean([data['title'], notification?.title], category);
    final body = _firstClean([
      data['description'],
      data['details'],
      data['content'],
      data['text'],
      data['body'],
      data['message'],
      data['alert'],
      data['headline'],
      notification?.body,
    ], category);
    return (title, body);
  }

  static Future<void> _handleIncomingMessage(RemoteMessage message) async {
    RefreshBus.instance.notify(reason: 'push_notification');
    final data = message.data;
    final isChatForActiveRoom =
        data['type'] == 'chat_message' &&
        ChatService.instance.isViewing('${data['roomId'] ?? ''}');
    final (title, body) = _resolveNotificationTitleAndBody(
      message.notification,
      data,
    );
    if (!isChatForActiveRoom && (title.isNotEmpty || body.isNotEmpty)) {
      final imageUrl =
          (data['image'] ??
                  data['imageUrl'] ??
                  data['image_url'] ??
                  message.notification?.android?.imageUrl ??
                  message.notification?.apple?.imageUrl)
              ?.toString()
              .trim();
      await FCMService.instance.showLocalNotificationDirect(
        title: title,
        body: body,
        imageUrl: (imageUrl != null && imageUrl.isNotEmpty) ? imageUrl : null,
        data: data,
      );
    }
    await DatasetSync.instance.applyPush(data);
  }

  Future<String> _firebaseRegistration() {
    final messaging = FirebaseMessaging.instance;
    _registrationListener ??= messaging.onRegistered.listen(
      (id) async {
        final changed = _cachedToken != null && _cachedToken != id;
        final wasUnavailable = !_apnsAvailable;
        _cachedToken = id;
        _apnsAvailable = true;
        try {
          await _sendTokenToBackend(id);
          if (changed || wasUnavailable) await _subscribeToDefaultTopics();
        } catch (error) {
          unawaited(
            AppLog.write('FCM registration sync failed: ${error.runtimeType}'),
          );
        }
      },
      onError: (Object error) {
        unawaited(
          AppLog.write('FCM registration failed: ${error.runtimeType}'),
        );
      },
    );
    return (_registration ??= PushRegistration(
      events: messaging.onRegistered,
      register: messaging.register,
    )).get();
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
          await ensureFirebase();
          final token = await _firebaseRegistration();

          _cachedToken = token;
          return token;
        } catch (e) {
          return null;
        }
      }
    }
    try {
      await ensureFirebase();
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
      final token = await _firebaseRegistration();

      _cachedToken = token;
      return token;
    } catch (e) {
      return null;
    }
  }

  Future<void> _sendTokenToBackend(String token) async {
    try {
      await _deviceRegistry().register(
        token: token,
        platform: kIsWeb
            ? (isChromeRuntimeAvailable()
                  ? PreConnectPushConfig.chromeExtensionPlatform
                  : 'web')
            : defaultTargetPlatform.name.toLowerCase(),
      );
    } catch (error) {
      unawaited(AppLog.write('FCM device registration failed: $error'));
    }
  }

  PushDeviceRegistry _deviceRegistry() {
    return PushDeviceRegistry(
      registerUrl:
          '${ApiConfig.realtimeApiBase}${PreConnectPushConfig.registerDevicePath}',
      unregisterUrl:
          '${ApiConfig.realtimeApiBase}${PreConnectPushConfig.unregisterDevicePath}',
      client: HttpUtils.client,
    );
  }

  Future<void> _syncToken() async {
    final token = await _getToken();

    if (token != null) {
      unawaited(_sendTokenToBackend(token));
    }
  }

  Future<void> _postTopicWeb(String path, String token, String topic) async {
    final url = '${ApiConfig.realtimeApiBase}$path';
    await _deviceRegistry().post(url, {'token': token, 'topic': topic});
  }

  Future<bool> _subscribeToTopicWeb(String token, String topic) async {
    try {
      await _postTopicWeb(
        PreConnectPushConfig.subscribeTopicPath,
        token,
        topic,
      );
      unawaited(AppLog.write('FCM topic subscribed: $topic'));
      return true;
    } catch (error) {
      unawaited(AppLog.write('FCM topic subscription failed ($topic): $error'));
      return false;
    }
  }

  Future<bool> _unsubscribeFromTopicWeb(String token, String topic) async {
    try {
      await _postTopicWeb(
        PreConnectPushConfig.unsubscribeTopicPath,
        token,
        topic,
      );
      unawaited(AppLog.write('FCM topic unsubscribed: $topic'));
      return true;
    } catch (error) {
      unawaited(
        AppLog.write('FCM topic unsubscription failed ($topic): $error'),
      );
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
      return _subscribeToTopicWeb(token, topic);
    }
    if ((defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS) &&
        !_apnsAvailable) {
      return false;
    }

    try {
      await ensureFirebase();
      await FirebaseMessaging.instance.subscribeToTopic(topic);
    } catch (error) {
      unawaited(AppLog.write('Native FCM topic subscription failed: $error'));
      return false;
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
      return _unsubscribeFromTopicWeb(token, topic);
    }
    if ((defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS) &&
        !_apnsAvailable) {
      return false;
    }

    try {
      await ensureFirebase();
      await FirebaseMessaging.instance.unsubscribeFromTopic(topic);
    } catch (error) {
      unawaited(AppLog.write('Native FCM topic unsubscription failed: $error'));
      return false;
    }
    return true;
  }

  Future<void> unregisterDevice() async {
    if (!isSupported) return;
    try {
      final token = await _getToken();
      if (token == null) return;
      await _deviceRegistry().unregister(token);
    } catch (error) {
      unawaited(AppLog.write('FCM device unregistration failed: $error'));
    }
  }

  Future<bool> requestNotificationPermission() async {
    if (!isSupported) return false;

    if (kIsWeb && isChromeRuntimeAvailable()) return true;

    if (kIsWeb) {
      try {
        await ensureFirebase();
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
      await ensureFirebase();
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
      await ensureFirebase();
      final settings = await FirebaseMessaging.instance
          .getNotificationSettings();
      return settings.authorizationStatus == AuthorizationStatus.authorized;
    } catch (e) {
      return false;
    }
  }

  Future<void> init() async {
    if (isChromeRuntimeAvailable()) return;
    if (!isSupported) return;
    await ensureFirebase();
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

  Future<Set<String>> _topicsToSubscribe() async {
    final topics = <String>{...PreConnectPushConfig.defaultTopics};
    try {
      final url = Uri.parse('${ApiConfig.realtimeApiBase}/push/topics');
      final response = await HttpUtils.client
          .get(url)
          .timeout(const Duration(seconds: 3));
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is String && item.trim().isNotEmpty) {
              topics.add(item.trim());
            }
          }
        }
      }
    } catch (_) {}
    return topics;
  }

  Future<Set<String>> _pinnedSeatTopics() async {
    try {
      final pinned = await CoursePinStore.load(
        PreConnectPushConfig.seatStatusPinScope,
      );
      return {for (final seat in pinned) PreConnectPushConfig.seatTopic(seat)};
    } catch (error) {
      unawaited(AppLog.write('FCM pinned seat load failed: $error'));
      return <String>{};
    }
  }

  Future<void> _subscribeAll(
    Iterable<String> topics,
    Future<Object?> Function(String topic) subscribe,
  ) => Future.wait<Object?>(topics.map(subscribe));

  Future<void> _initWeb() async {
    final token = await _getToken();
    if (token == null) return;

    try {
      final (topics, pinned, chat) = await (
        _topicsToSubscribe(),
        _pinnedSeatTopics(),
        ChatService.savedPushTopics(),
      ).wait;
      await _subscribeAll({
        ...topics,
        ...pinned,
        ...chat,
      }, (topic) => _subscribeToTopicWeb(token, topic));
    } catch (error) {
      unawaited(AppLog.write('FCM topic restore failed: $error'));
    }

    if (!isChromeRuntimeAvailable()) {
      try {
        FirebaseMessaging.onMessage.listen(
          (message) => unawaited(_handleIncomingMessage(message)),
        );
      } catch (error) {
        unawaited(AppLog.write('FCM foreground listener setup failed: $error'));
      }
    }
  }

  Future<void> _subscribeToDefaultTopics() async {
    final token = await _getToken();
    final (topics, pinned, chat) = await (
      _topicsToSubscribe(),
      _pinnedSeatTopics(),
      ChatService.savedPushTopics(),
    ).wait;
    await _subscribeAll({
      ...topics,
      ...pinned,
      ...chat,
    }, (topic) => _subscribeToTopicInternal(topic, cachedToken: token));
  }

  Future<void> _initNative() async {
    FirebaseMessaging.onMessage.listen(
      (message) => unawaited(_handleIncomingMessage(message)),
    );

    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageTap);
    FirebaseMessaging.instance.getInitialMessage().then((message) {
      if (message != null) {
        _handleMessageTap(message);
      }
    });

    await _subscribeToDefaultTopics();
  }

  Future<void> _setupLocalNotifications() async {
    await ensureLocalNotificationsInitialized();
  }

  static DarwinNotificationDetails _darwinDetails([
    List<DarwinNotificationAttachment>? attachments,
  ]) => DarwinNotificationDetails(
    presentAlert: true,
    presentBadge: true,
    presentSound: true,
    presentBanner: true,
    presentList: true,
    interruptionLevel: InterruptionLevel.timeSensitive,
    attachments: attachments,
  );

  static NotificationDetails _notificationDetails({
    StyleInformation? androidStyle,
    List<DarwinNotificationAttachment>? darwinAttachments,
  }) => NotificationDetails(
    android: AndroidNotificationDetails(
      'high_importance_channel',
      'High Importance Notifications',
      importance: Importance.max,
      priority: Priority.max,
      icon: 'status_icon',
      playSound: true,
      enableVibration: true,
      channelShowBadge: true,
      visibility: NotificationVisibility.public,
      category: AndroidNotificationCategory.event,
      styleInformation: androidStyle,
    ),
    iOS: _darwinDetails(darwinAttachments),
    macOS: _darwinDetails(darwinAttachments),
  );

  Future<(StyleInformation?, List<DarwinNotificationAttachment>?)>
  _imageAttachments(String imageUrl) async {
    try {
      final response = await HttpUtils.client
          .get(Uri.parse(imageUrl))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) return (null, null);
      if (defaultTargetPlatform == TargetPlatform.android) {
        return (
          BigPictureStyleInformation(
            ByteArrayAndroidBitmap(response.bodyBytes),
            hideExpandedLargeIcon: true,
          ),
          null,
        );
      }
      final tempDir = await AppPaths.temporaryDirectory();
      final tempFile = File('${tempDir.path}/${imageUrl.hashCode}.png');
      await tempFile.writeAsBytes(response.bodyBytes);
      return (null, [DarwinNotificationAttachment(tempFile.path)]);
    } catch (error) {
      unawaited(AppLog.write('Notification image attachment failed: $error'));
      return (null, null);
    }
  }

  Future<void> showLocalNotificationDirect({
    required String title,
    required String body,
    String? imageUrl,
    Map<String, dynamic> data = const {},
    int? id,
  }) async {
    if (kIsWeb) return;
    await ensureLocalNotificationsInitialized();
    final category = _notificationCategory(data);
    final resolvedTitle = cleanNotificationDescription(
      title.trim(),
      category: category,
    );
    final shownTitle = resolvedTitle.isNotEmpty
        ? resolvedTitle
        : (category.isNotEmpty ? category : 'PreConnect');
    final resolvedBody = cleanNotificationDescription(
      body.trim(),
      category: category,
    );
    final shownBody = resolvedBody.isNotEmpty
        ? resolvedBody
        : (category.isNotEmpty ? category : 'Open PreConnect for details.');
    final notifId =
        id ?? ((shownTitle.hashCode ^ shownBody.hashCode) & 0x7FFFFFFF);
    final (
      androidStyle,
      darwinAttachments,
    ) = (imageUrl != null && imageUrl.isNotEmpty)
        ? await _imageAttachments(imageUrl)
        : (null, null);
    await _localNotifications.show(
      id: notifId,
      title: shownTitle,
      body: shownBody,
      payload: jsonEncode(data),
      notificationDetails: _notificationDetails(
        androidStyle: androidStyle,
        darwinAttachments: darwinAttachments,
      ),
    );
  }

  void _handleMessageTap(RemoteMessage message) {
    _handleNotificationTapAction(message.data);
  }

  void _handleNotificationTapAction(Map<String, dynamic> data) {
    if (data['type'] == 'chat_message') {
      _openChat?.call('${data['roomId'] ?? ''}');
      return;
    }
    final action = data['payload'] ?? data['action'];
    if (action == 'captive_wifi') {
      _openCaptiveWifi?.call();
      return;
    }
    if (action == 'notifications') {
      _openNotifications?.call();
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
        final handler = _openUrl;
        if (handler != null) {
          unawaited(handler(url));
        } else {
          final uri = Uri.parse(url);
          unawaited(launchUrl(uri, mode: LaunchMode.inAppBrowserView));
        }
      } catch (error) {
        unawaited(AppLog.write('Notification action failed: $error'));
      }
    } else {
      _openNotifications?.call();
    }
  }

  Future<void> sendConfirmationNotification(
    String courseCode,
    String sectionName,
  ) async {
    if (!isSupported) return;
    try {
      await showLocalNotificationDirect(
        id: Object.hash(courseCode, sectionName) & 0x7fffffff,
        title: 'Seat Alerts Enabled',
        body:
            "You'll be notified when a seat becomes available in $courseCode Section $sectionName.",
      );
    } catch (error) {
      unawaited(AppLog.write('Confirmation notification send failed: $error'));
    }
  }
}
