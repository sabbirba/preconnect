import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:preconnect/api/api_client.dart';
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/api/seat_status_service.dart';
import 'package:preconnect/pages/home.dart';
import 'package:preconnect/pages/home_tab.dart';
import 'package:preconnect/tools/build_info.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PushNotificationsService {
  PushNotificationsService._internal();

  static final PushNotificationsService _instance =
      PushNotificationsService._internal();
  factory PushNotificationsService() => _instance;

  static const String _installIdKey = 'vps_push_install_id_v1';
  static const Duration _pollInterval = Duration(seconds: 30);

  final ApiClient _client = ApiClient();
  Timer? _pollTimer;
  bool _initialized = false;
  String? _installId;

  Future<void> initialize() async {
    if (_initialized || !_isSupportedPlatform()) return;
    final prefs = await SharedPreferences.getInstance();
    _installId = prefs.getString(_installIdKey)?.trim();
    if (_installId == null || _installId!.isEmpty) {
      _installId = _generateInstallId();
      await prefs.setString(_installIdKey, _installId!);
    }
    await _syncDevice();
    unawaited(pollPendingAlerts());
    _pollTimer ??= Timer.periodic(_pollInterval, (_) {
      unawaited(pollPendingAlerts());
    });
    _initialized = true;
  }

  Future<bool> hasNotificationPermission() async => _isSupportedPlatform();

  Future<bool> ensureNotificationPermission() async => _isSupportedPlatform();

  Future<bool> openSystemNotificationSettings() async => true;

  Future<void> dispose() async {
    _pollTimer?.cancel();
    _pollTimer = null;
    _initialized = false;
  }

  Future<void> pollPendingAlerts() async {
    if (!_isSupportedPlatform()) return;
    final token = _installId;
    if (token == null || token.isEmpty) return;
    try {
      final response = await _client.authenticatedGet(
        '${ApiConfig.pushAlertsBase}/push/alerts/pending?token=${Uri.encodeComponent(token)}',
        acceptedStatusCodes: const <int>{200},
      );
      final decoded = jsonDecode(response.body);
      final items = decoded is Map ? decoded['items'] : null;
      if (items is! List) return;
      for (final item in items.whereType<Map>()) {
        await SeatAlertSyncService().handleIncomingSeatAlertPayload(
          item.cast<String, dynamic>(),
        );
      }
    } catch (_) {}
  }

  Future<void> _syncDevice() async {
    final token = _installId;
    if (token == null || token.isEmpty) return;
    final locale = WidgetsBinding.instance.platformDispatcher.locale
        .toLanguageTag();
    final appVersion = await BuildInfo.fullVersion();
    await SeatAlertSyncService().configureDeviceToken(token);
    try {
      await SeatAlertSyncService().registerDevice(
        platform: defaultTargetPlatform.name,
        locale: locale,
        appVersion: appVersion,
      );
      final configs = await SeatStatusService().loadSeatAlertConfigs();
      await SeatAlertSyncService().syncAllSeatAlertConfigs(configs);
    } catch (_) {}
  }

  bool _isSupportedPlatform() {
    if (kIsWeb) return false;
    final platform = defaultTargetPlatform;
    return platform == TargetPlatform.android ||
        platform == TargetPlatform.iOS ||
        platform == TargetPlatform.macOS;
  }

  String _generateInstallId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}

class SeatAlertSyncService {
  SeatAlertSyncService._internal();

  static final SeatAlertSyncService _instance = SeatAlertSyncService._internal();
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
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_pushEnabledKey) ?? false;
    final token = (prefs.getString(_deviceTokenKey) ?? '').trim();
    _deviceToken = enabled && token.isNotEmpty ? token : null;
  }

  Future<void> configureDeviceToken(String token) async {
    final normalized = token.trim();
    final prefs = await SharedPreferences.getInstance();
    if (normalized.isEmpty) {
      _deviceToken = null;
      await prefs.remove(_deviceTokenKey);
      await prefs.setBool(_pushEnabledKey, false);
      return;
    }
    _deviceToken = normalized;
    await prefs.setString(_deviceTokenKey, normalized);
    await prefs.setBool(_pushEnabledKey, true);
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
    final prefs = await SharedPreferences.getInstance();
    _deviceToken = null;
    await prefs.remove(_deviceTokenKey);
    await prefs.setBool(_pushEnabledKey, false);
  }

  Future<void> handleIncomingSeatAlertPayload(
    Map<String, dynamic> payload,
  ) async {
    final kind = '${payload['kind'] ?? payload['type'] ?? ''}'.trim();
    if (kind != 'seat_alert') return;
    final sectionId = int.tryParse('${payload['sectionId'] ?? ''}');
    if (sectionId == null || sectionId <= 0) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_pendingSectionIdKey, sectionId);
    await prefs.setString(
      _pendingSourceKey,
      '${payload['source'] ?? 'vps'}'.trim(),
    );
    HomePage.requestShortcutTab(HomeTab.seatStatus);
  }

  Future<int?> consumePendingSectionId() async {
    final prefs = await SharedPreferences.getInstance();
    final sectionId = prefs.getInt(_pendingSectionIdKey);
    if (sectionId != null) {
      await prefs.remove(_pendingSectionIdKey);
      await prefs.remove(_pendingSourceKey);
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
