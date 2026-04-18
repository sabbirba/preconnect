import 'dart:async';
import 'dart:convert';

import 'package:background_fetch/background_fetch.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:preconnect/api/api_client.dart';
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/api/notification_service.dart';
import 'package:preconnect/api/seat_status_service.dart';
import 'package:preconnect/model/seat_status_info.dart';
import 'package:preconnect/pages/home.dart';
import 'package:preconnect/pages/home_tab.dart';
import 'package:preconnect/tools/build_info.dart';
import 'package:preconnect/tools/refresh_bus.dart';
import 'package:http/http.dart' as http;
import 'package:preconnect/tools/app_storage.dart';

@pragma('vm:entry-point')
void backgroundFetchHeadlessTask(HeadlessTask task) async {
  String taskId = task.taskId;

  try {
    final service = PushNotificationsService();
    await service._prepareForBackgroundRun();
    await service._checkSeatAlerts();
    await service._pollServerPushAlerts();
  } catch (_) {}

  await BackgroundFetch.finish(taskId);
}

class PushNotificationsService {
  PushNotificationsService._internal();

  static final PushNotificationsService _instance =
      PushNotificationsService._internal();
  factory PushNotificationsService() => _instance;

  static const String _deviceTokenKey = 'vps_push_device_token_v1';
  static const Duration _pollInterval = Duration(seconds: 30);
  static const Duration _streamReconnectDelay = Duration(seconds: 5);
  static const Duration _payloadDedupeWindow = Duration(seconds: 90);
  static const int _maxDedupeEntries = 400;

  final ApiClient _client = ApiClient();
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  final Connectivity _connectivity = Connectivity();
  final SeatStatusService _seatStatusService = SeatStatusService();

  http.Client? _sseClient;
  StreamSubscription<String>? _sseSubscription;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Timer? _pollTimer;
  Timer? _reconnectTimer;
  bool _initialized = false;
  String? _deviceToken;
  bool _isConnected = false;
  bool _serverPollInFlight = false;
  final Map<int, int> _lastNotifiedSeatCount = <int, int>{};
  final Map<String, int> _recentPayloadMs = <String, int>{};
  final List<String> _pendingSseDataLines = <String>[];

  Future<void> initialize() async {
    if (_initialized || !_isSupportedPlatform()) return;

    try {
      await _initializeLocalNotifications();
      await _initializeBackgroundFetch();
      await _syncDevice();
      await _connectToSeatStream();
      _setupConnectivityListener();
      _startPollingFallback();
      _initialized = true;
    } catch (e) {
      if (kDebugMode) {
        print('Error initializing push notifications: $e');
      }
    }
  }

  Future<void> _initializeLocalNotifications() async {
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
        );

    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(settings: initSettings);
  }

  Future<void> _initializeBackgroundFetch() async {
    try {
      await BackgroundFetch.configure(
        BackgroundFetchConfig(
          minimumFetchInterval: 15,
          stopOnTerminate: false,
          enableHeadless: true,
          requiresBatteryNotLow: false,
          requiresDeviceIdle: false,
          requiresStorageNotLow: false,
          startOnBoot: true,
        ),
        backgroundFetchHeadlessTask,
      );
    } catch (e) {
      if (kDebugMode) {
        print('Background fetch initialization error: $e');
      }
    }
  }

  Future<void> _prepareForBackgroundRun() async {
    if (!_isSupportedPlatform()) return;

    try {
      await _initializeLocalNotifications();
    } catch (_) {}

    if (_deviceToken == null || _deviceToken!.trim().isEmpty) {
      final prefs = AppStorage.instance;
      final savedToken = (await prefs.getString(_deviceTokenKey) ?? '').trim();
      if (savedToken.isNotEmpty) {
        _deviceToken = savedToken;
      } else {
        _deviceToken = _generateDeviceToken();
        await prefs.setString(_deviceTokenKey, _deviceToken!);
      }
    }
  }

  Future<bool> hasNotificationPermission() async {
    if (!_isSupportedPlatform()) return false;
    final status = await Permission.notification.status;
    return status.isGranted;
  }

  Future<bool> ensureNotificationPermission() async {
    if (!_isSupportedPlatform()) return false;
    final status = await Permission.notification.request();
    return status.isGranted;
  }

  Future<bool> openSystemNotificationSettings() async {
    if (!_isSupportedPlatform()) return false;
    return await openAppSettings();
  }

  Future<void> dispose() async {
    await _sseSubscription?.cancel();
    _sseSubscription = null;
    _sseClient?.close();
    _sseClient = null;
    _connectivitySubscription?.cancel();
    _pollTimer?.cancel();
    _reconnectTimer?.cancel();
    _initialized = false;
    _isConnected = false;
  }

  Future<void> _syncDevice() async {
    final prefs = AppStorage.instance;
    final token = (await prefs.getString(_deviceTokenKey) ?? '').trim();

    _deviceToken = token.isNotEmpty ? token : _generateDeviceToken();
    if (_deviceToken != null) {
      final prefs = AppStorage.instance;
      await prefs.setString(_deviceTokenKey, _deviceToken!);
    }

    await SeatAlertSyncService().configureDeviceToken(_deviceToken ?? '');

    try {
      final locale = WidgetsBinding.instance.platformDispatcher.locale
          .toLanguageTag();
      final appVersion = await BuildInfo.fullVersion();

      await SeatAlertSyncService().registerDevice(
        platform: defaultTargetPlatform.name,
        locale: locale,
        appVersion: appVersion,
      );

      final configs = await SeatStatusService().loadSeatAlertConfigs();
      await SeatAlertSyncService().syncAllSeatAlertConfigs(configs);
    } catch (e) {
      if (kDebugMode) {
        print('Error syncing device: $e');
      }
    }
  }

  Future<void> _connectToSeatStream() async {
    _reconnectTimer?.cancel();

    try {
      await _sseSubscription?.cancel();
      _sseSubscription = null;
      _sseClient?.close();
      _sseClient = null;
      _pendingSseDataLines.clear();

      final baseUri = Uri.parse(_seatStatusService.seatStatusStreamUrl);
      final token = _deviceToken ?? '';
      final query = <String, String>{
        ...baseUri.queryParameters,
        if (token.isNotEmpty) 'token': token,
      };
      final streamUri = baseUri.replace(queryParameters: query);

      final client = http.Client();
      final request = http.Request('GET', streamUri)
        ..headers['Accept'] = 'text/event-stream'
        ..headers['Cache-Control'] = 'no-cache';

      final response = await client.send(request);
      if (response.statusCode != 200) {
        client.close();
        throw StateError('SSE stream returned HTTP ${response.statusCode}');
      }

      _sseClient = client;
      _sseSubscription = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            _handleSseLine,
            onError: _handleStreamError,
            onDone: _handleStreamDone,
          );

      _isConnected = true;
      if (kDebugMode) {
        print('Seat status SSE stream connected');
      }
    } catch (e) {
      if (kDebugMode) {
        print('SSE stream connection error: $e');
      }
      _isConnected = false;
      _scheduleStreamReconnect();
    }
  }

  void _handleSseLine(String line) {
    if (line.isEmpty) {
      _flushSseEvent();
      return;
    }

    if (line.startsWith(':')) {
      return;
    }

    if (line.startsWith('data:')) {
      _pendingSseDataLines.add(line.substring(5).trimLeft());
      return;
    }

    if (!line.startsWith('event:') && !line.startsWith('id:')) {
      _pendingSseDataLines.add(line.trim());
    }
  }

  void _flushSseEvent() {
    if (_pendingSseDataLines.isEmpty) return;
    final payloadText = _pendingSseDataLines.join('\n').trim();
    _pendingSseDataLines.clear();
    if (payloadText.isEmpty) return;
    _handleStreamMessage(payloadText);
  }

  void _handleStreamMessage(String message) {
    try {
      final decoded = jsonDecode(message);
      if (decoded is Map<String, dynamic>) {
        final kind = '${decoded['kind'] ?? decoded['type'] ?? ''}'.trim();
        if (kind.isNotEmpty) {
          unawaited(_handleIncomingPushPayload(decoded));
        } else {
          unawaited(_processSeatUpdate(decoded));
        }
        return;
      }

      if (decoded is List) {
        for (final item in decoded.whereType<Map>()) {
          final data = item.cast<String, dynamic>();
          final kind = '${data['kind'] ?? data['type'] ?? ''}'.trim();
          if (kind.isNotEmpty) {
            unawaited(_handleIncomingPushPayload(data));
          } else {
            unawaited(_processSeatUpdate(data));
          }
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error handling SSE stream message: $e');
      }
    }
  }

  void _handleStreamError(dynamic error) {
    if (kDebugMode) {
      print('SSE stream error: $error');
    }
    _isConnected = false;
    _pendingSseDataLines.clear();
    _sseClient?.close();
    _sseClient = null;
    _scheduleStreamReconnect();
  }

  void _handleStreamDone() {
    if (kDebugMode) {
      print('SSE stream closed');
    }
    _isConnected = false;
    _pendingSseDataLines.clear();
    _sseClient?.close();
    _sseClient = null;
    _scheduleStreamReconnect();
  }

  void _scheduleStreamReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(_streamReconnectDelay, _connectToSeatStream);
  }

  void _setupConnectivityListener() {
    _connectivitySubscription?.cancel();
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen((
      result,
    ) async {
      final isOnline = !result.contains(ConnectivityResult.none);
      if (isOnline && !_isConnected) {
        await _connectToSeatStream();
      }
    });
  }

  void _startPollingFallback() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_pollInterval, (_) {
      unawaited(_pollServerPushAlerts());
      if (!_isConnected) {
        unawaited(_checkSeatAlerts());
      }
    });
  }

  Future<void> _pollServerPushAlerts() async {
    final token = _deviceToken;
    if (token == null || token.isEmpty) return;
    if (_serverPollInFlight) return;

    _serverPollInFlight = true;

    try {
      final response = await _client.authenticatedGet(
        '${ApiConfig.pushAlertsBase}/push/alerts/pending?token=${Uri.encodeComponent(token)}',
        acceptedStatusCodes: const <int>{200},
      );
      final decoded = jsonDecode(response.body);
      final items = decoded is Map ? decoded['items'] : null;
      if (items is! List) return;

      for (final item in items.whereType<Map>()) {
        await _handleIncomingPushPayload(item.cast<String, dynamic>());
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error polling server push alerts: $e');
      }
    } finally {
      _serverPollInFlight = false;
    }
  }

  Future<void> _processSeatUpdate(Map<String, dynamic> streamData) async {
    try {
      final configs = await _seatStatusService.loadSeatAlertConfigs();
      if (configs.isEmpty) return;

      for (final entry in configs.entries) {
        final sectionId = entry.key;
        final config = entry.value;

        final sectionData = _extractSectionData(streamData, sectionId);
        if (sectionData == null) continue;

        await _evaluateAlertRules(sectionId, config, sectionData);
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error processing seat update: $e');
      }
    }
  }

  Future<void> _checkSeatAlerts() async {
    try {
      final configs = await _seatStatusService.loadSeatAlertConfigs();
      if (configs.isEmpty) return;

      final allDetails = await _seatStatusService
          .fetchAllSectionsDetailsFromApi();

      for (final entry in configs.entries) {
        final sectionId = entry.key;
        final config = entry.value;
        final details = allDetails[sectionId];

        if (details == null) continue;

        final sectionData = {
          'sectionId': sectionId,
          'availableSeats':
              details.section.capacity - details.section.consumedSeat,
          'totalSeats': details.section.capacity,
        };

        await _evaluateAlertRules(sectionId, config, sectionData);
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error checking seat alerts: $e');
      }
    }
  }

  Future<void> _evaluateAlertRules(
    int sectionId,
    SeatAlertConfig config,
    Map<String, dynamic> sectionData,
  ) async {
    final availableSeats = (sectionData['availableSeats'] ?? 0) as int;
    final lastNotified = _lastNotifiedSeatCount[sectionId] ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    final lastNotifiedTime = config.lastChangeNotifiedAtMs ?? 0;
    final cooldownMs = config.changeCooldownMinutes * 60 * 1000;

    bool shouldNotify = false;
    String? reason;

    if (config.notifyOnAvailable && availableSeats > 0 && lastNotified <= 0) {
      shouldNotify = true;
      reason = 'seats_available';
    } else if (config.thresholdSeats != null &&
        availableSeats >= config.thresholdSeats! &&
        lastNotified < config.thresholdSeats!) {
      shouldNotify = true;
      reason = 'threshold_reached';
    } else if (config.notifyOnAnyChange &&
        lastNotified != availableSeats &&
        (now - lastNotifiedTime) > cooldownMs) {
      shouldNotify = true;
      reason = 'seats_changed';
    }

    if (shouldNotify) {
      _lastNotifiedSeatCount[sectionId] = availableSeats;
      await _showNotification(sectionId, availableSeats, reason!);

      final updated = config.copyWith(lastChangeNotifiedAtMs: now);
      await _seatStatusService.saveSeatAlertConfig(updated);
    }
  }

  Map<String, dynamic>? _extractSectionData(
    Map<String, dynamic> streamData,
    int sectionId,
  ) {
    try {
      final sections = streamData['sections'] as Map?;
      if (sections == null) return null;

      final section = sections[sectionId.toString()] as Map?;
      if (section == null) return null;

      return {
        'sectionId': sectionId,
        'availableSeats':
            int.tryParse('${section['availableSeats'] ?? 0}') ?? 0,
        'totalSeats': int.tryParse('${section['totalSeats'] ?? 0}') ?? 0,
      };
    } catch (_) {
      return null;
    }
  }

  Future<void> _showNotification(
    int sectionId,
    int availableSeats,
    String reason,
  ) async {
    try {
      String title;
      String body;

      switch (reason) {
        case 'seats_available':
          title = 'Seat Available';
          body = '$availableSeats seats now available in section $sectionId';
          break;
        case 'threshold_reached':
          title = 'Threshold Reached';
          body = '$availableSeats seats available in section $sectionId';
          break;
        case 'seats_changed':
          title = 'Seat Change';
          body = 'Seats updated to $availableSeats in section $sectionId';
          break;
        default:
          title = 'Seat Alert';
          body = 'Section $sectionId: $availableSeats seats available';
      }

      const AndroidNotificationDetails androidDetails =
          AndroidNotificationDetails(
            'seat_alerts',
            'Seat Alerts',
            channelDescription: 'Real-time seat availability notifications',
            importance: Importance.max,
            priority: Priority.high,
            showWhen: true,
          );

      const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      const NotificationDetails details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _localNotifications.show(
        id: sectionId.hashCode,
        title: title,
        body: body,
        notificationDetails: details,
        payload: jsonEncode({'sectionId': sectionId}),
      );

      await SeatAlertSyncService().handleIncomingSeatAlertPayload({
        'kind': 'seat_alert',
        'sectionId': sectionId,
        'source': 'stream',
      });
    } catch (e) {
      if (kDebugMode) {
        print('Error showing notification: $e');
      }
    }
  }

  Future<void> _handleIncomingPushPayload(Map<String, dynamic> payload) async {
    final kind = '${payload['kind'] ?? payload['type'] ?? ''}'.trim();
    if (kind.isEmpty) return;
    if (_isDuplicatePayload(payload, kind: kind)) return;

    if (kind == 'seat_alert') {
      final sectionId = int.tryParse('${payload['sectionId'] ?? ''}');
      if (sectionId == null || sectionId <= 0) return;

      final availableSeats =
          int.tryParse('${payload['availableSeats'] ?? ''}') ??
          int.tryParse('${payload['seats'] ?? ''}') ??
          1;

      await _showNotification(sectionId, availableSeats, 'seats_available');
      return;
    }

    if (kind == 'announcement' ||
        kind == 'news' ||
        kind == 'activity' ||
        kind == 'notification' ||
        kind == 'connect_notification') {
      await _showGenericNotification(payload, kind: kind);
      unawaited(NotificationService().fetchRecentNotifications());
      unawaited(
        NotificationService().getScraperContentFeed(forceRefresh: true),
      );
      RefreshBus.instance.notify(reason: 'notifications');
    }
  }

  bool _isDuplicatePayload(
    Map<String, dynamic> payload, {
    required String kind,
  }) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final cutoffMs = nowMs - _payloadDedupeWindow.inMilliseconds;
    _recentPayloadMs.removeWhere((_, ts) => ts < cutoffMs);

    final payloadKey = _payloadKey(payload, kind: kind);
    final seenAt = _recentPayloadMs[payloadKey];
    if (seenAt != null &&
        nowMs - seenAt < _payloadDedupeWindow.inMilliseconds) {
      return true;
    }
    _recentPayloadMs[payloadKey] = nowMs;

    if (_recentPayloadMs.length > _maxDedupeEntries) {
      final entries = _recentPayloadMs.entries.toList()
        ..sort((a, b) => a.value.compareTo(b.value));
      final overflow = _recentPayloadMs.length - _maxDedupeEntries;
      for (var i = 0; i < overflow; i++) {
        _recentPayloadMs.remove(entries[i].key);
      }
    }

    return false;
  }

  String _payloadKey(Map<String, dynamic> payload, {required String kind}) {
    final stableId =
        '${payload['id'] ?? payload['notificationId'] ?? payload['uuid'] ?? ''}'
            .trim();
    final sectionId = '${payload['sectionId'] ?? ''}'.trim();
    final title = '${payload['title'] ?? payload['subject'] ?? ''}'.trim();
    final body =
        '${payload['message'] ?? payload['body'] ?? payload['details'] ?? ''}'
            .trim();
    final ts =
        '${payload['createdOn'] ?? payload['timestamp'] ?? payload['ts'] ?? ''}'
            .trim();
    return [kind, stableId, sectionId, title, body, ts].join('|');
  }

  Future<void> _showGenericNotification(
    Map<String, dynamic> payload, {
    required String kind,
  }) async {
    final rawTitle = '${payload['title'] ?? payload['subject'] ?? ''}'.trim();
    final rawBody =
        '${payload['message'] ?? payload['body'] ?? payload['details'] ?? ''}'
            .trim();
    final title = rawTitle.isEmpty ? 'Notification' : rawTitle;
    final body = rawBody.isEmpty
        ? 'You have a new ${kind.replaceAll('_', ' ')} update.'
        : rawBody;
    final id =
        int.tryParse('${payload['id'] ?? payload['notificationId'] ?? ''}') ??
        payload.hashCode;

    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          'general_alerts',
          'General Alerts',
          channelDescription: 'General app notifications and updates',
          importance: Importance.max,
          priority: Priority.high,
          showWhen: true,
        );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _localNotifications.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: details,
      payload: jsonEncode(payload),
    );
  }

  bool _isSupportedPlatform() {
    if (kIsWeb) return false;
    final platform = defaultTargetPlatform;
    return platform == TargetPlatform.android || platform == TargetPlatform.iOS;
  }

  String _generateDeviceToken() {
    return '${DateTime.now().millisecondsSinceEpoch}_${defaultTargetPlatform.name}';
  }
}

class SeatAlertSyncService {
  SeatAlertSyncService._internal();

  static final SeatAlertSyncService _instance =
      SeatAlertSyncService._internal();
  factory SeatAlertSyncService() => _instance;

  static const String _pushEnabledKey = 'seat_alert_push_enabled_v1';
  static const String _deviceTokenKey = 'seat_alert_push_device_token_v1';
  static const String _pendingSectionIdKey =
      'seat_alert_push_pending_section_id_v1';
  static const String _pendingSourceKey = 'seat_alert_push_pending_source_v1';

  final ApiClient _client = ApiClient();
  String? _deviceToken;

  bool get isEnabled => _deviceToken != null && _deviceToken!.trim().isNotEmpty;

  Future<void> initialize() async {
    final enabled =
        (await AppStorage.instance.getBool(_pushEnabledKey)) ?? false;
    final token = (await AppStorage.instance.getString(_deviceTokenKey) ?? '')
        .trim();
    _deviceToken = enabled && token.isNotEmpty ? token : null;
  }

  Future<void> configureDeviceToken(String token) async {
    final normalized = token.trim();
    if (normalized.isEmpty) {
      _deviceToken = null;
      await AppStorage.instance.remove(_deviceTokenKey);
      await AppStorage.instance.setBool(_pushEnabledKey, false);
      return;
    }
    _deviceToken = normalized;
    await AppStorage.instance.setString(_deviceTokenKey, normalized);
    await AppStorage.instance.setBool(_pushEnabledKey, true);
  }

  Future<void> registerDevice({
    required String platform,
    String? locale,
    String? appVersion,
  }) async {
    await initialize();
    final token = _deviceToken;
    if (token == null || token.isEmpty) return;
    final payload = <String, dynamic>{
      'token': token,
      'platform': platform,
      if (locale != null && locale.trim().isNotEmpty) 'locale': locale.trim(),
      if (appVersion != null && appVersion.trim().isNotEmpty)
        'appVersion': appVersion.trim(),
    };
    await _client.authenticatedRequest(
      'POST',
      '${ApiConfig.pushAlertsBase}${ApiConfig.pushDeviceRegisterPath}',
      body: jsonEncode(payload),
      additionalHeaders: const <String, String>{
        'Content-Type': 'application/json',
      },
      acceptedStatusCodes: const <int>{200, 201, 204},
    );
  }

  Future<void> unregisterDevice() async {
    await initialize();
    final token = _deviceToken;
    if (token == null || token.isEmpty) return;
    await _client.authenticatedRequest(
      'POST',
      '${ApiConfig.pushAlertsBase}${ApiConfig.pushDeviceUnregisterPath}',
      body: jsonEncode(<String, dynamic>{'token': token}),
      additionalHeaders: const <String, String>{
        'Content-Type': 'application/json',
      },
      acceptedStatusCodes: const <int>{200, 204},
    );
  }

  Future<void> syncSeatAlertConfig(SeatAlertConfig config) async {
    await initialize();
    final token = _deviceToken;
    if (token == null || token.isEmpty || !config.hasAnyRule) return;
    final payload = <String, dynamic>{
      'token': token,
      'sectionId': config.sectionId,
      'rules': _rulesPayload(config),
    };
    await _client.authenticatedRequest(
      'PUT',
      '${ApiConfig.pushAlertsBase}${ApiConfig.seatAlertSubscriptionPath(config.sectionId)}',
      body: jsonEncode(payload),
      additionalHeaders: const <String, String>{
        'Content-Type': 'application/json',
      },
      acceptedStatusCodes: const <int>{200, 201, 204},
    );
  }

  Future<void> removeSeatAlertConfig(int sectionId) async {
    await initialize();
    final token = _deviceToken;
    if (token == null || token.isEmpty) return;
    await _client.authenticatedRequest(
      'DELETE',
      '${ApiConfig.pushAlertsBase}${ApiConfig.seatAlertSubscriptionPath(sectionId)}',
      body: jsonEncode(<String, dynamic>{'token': token}),
      additionalHeaders: const <String, String>{
        'Content-Type': 'application/json',
      },
      acceptedStatusCodes: const <int>{200, 204},
    );
  }

  Future<void> syncAllSeatAlertConfigs(
    Map<int, SeatAlertConfig> configs,
  ) async {
    await initialize();
    final token = _deviceToken;
    if (token == null || token.isEmpty) return;
    final subscriptions = configs.values
        .where((config) => config.hasAnyRule)
        .map(
          (config) => <String, dynamic>{
            'sectionId': config.sectionId,
            'rules': _rulesPayload(config),
          },
        )
        .toList();
    await _client.authenticatedRequest(
      'PUT',
      '${ApiConfig.pushAlertsBase}${ApiConfig.seatAlertSubscriptionsPath}',
      body: jsonEncode(<String, dynamic>{
        'token': token,
        'subscriptions': subscriptions,
      }),
      additionalHeaders: const <String, String>{
        'Content-Type': 'application/json',
      },
      acceptedStatusCodes: const <int>{200, 201, 204},
    );
  }

  Future<void> clearAll() async {
    await unregisterDevice();
    _deviceToken = null;
    await AppStorage.instance.remove(_deviceTokenKey);
    await AppStorage.instance.setBool(_pushEnabledKey, false);
  }

  Future<void> handleIncomingSeatAlertPayload(
    Map<String, dynamic> payload,
  ) async {
    final kind = '${payload['kind'] ?? payload['type'] ?? ''}'.trim();
    if (kind != 'seat_alert') return;
    final sectionId = int.tryParse('${payload['sectionId'] ?? ''}');
    if (sectionId == null || sectionId <= 0) return;
    await AppStorage.instance.setInt(_pendingSectionIdKey, sectionId);
    await AppStorage.instance.setString(
      _pendingSourceKey,
      '${payload['source'] ?? 'vps'}'.trim(),
    );
    HomePage.requestShortcutTab(HomeTab.seatStatus);
  }

  Future<int?> consumePendingSectionId() async {
    final sectionId = await AppStorage.instance.getInt(_pendingSectionIdKey);
    if (sectionId != null) {
      await AppStorage.instance.remove(_pendingSectionIdKey);
      await AppStorage.instance.remove(_pendingSourceKey);
    }
    return sectionId;
  }

  Map<String, dynamic> _rulesPayload(SeatAlertConfig config) {
    return <String, dynamic>{
      if (config.notifyOnAvailable)
        'available': <String, dynamic>{'oneTime': config.availableOneTime},
      if (config.thresholdSeats != null)
        'threshold': <String, dynamic>{
          'minSeats': config.thresholdSeats,
          'oneTime': config.thresholdOneTime,
        },
      if (config.notifyOnAnyChange)
        'changed': <String, dynamic>{
          'cooldownMinutes': config.changeCooldownMinutes,
        },
    };
  }
}
