import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class AndroidNetworkStatus {
  const AndroidNetworkStatus({
    required this.connected,
    required this.validated,
    required this.captive,
    required this.transport,
    required this.androidApi,
    required this.ssid,
    required this.captiveWifiUrl,
    required this.gatewayAddress,
    required this.canExtendSession,
    required this.sessionExpiryTimeMillis,
  });

  final bool connected;
  final bool validated;
  final bool captive;
  final String transport;
  final int androidApi;
  final String? ssid;
  final String? captiveWifiUrl;
  final String? gatewayAddress;
  final bool? canExtendSession;
  final int? sessionExpiryTimeMillis;

  factory AndroidNetworkStatus.fromMap(Map<dynamic, dynamic> map) {
    return AndroidNetworkStatus(
      connected: map['connected'] == true,
      validated: map['validated'] == true,
      captive: map['captive'] == true,
      transport: (map['transport'] as String?) ?? 'unknown',
      androidApi: (map['androidApi'] as num?)?.toInt() ?? 0,
      ssid: (map['ssid'] as String?)?.trim().isEmpty == true
          ? null
          : (map['ssid'] as String?),
      captiveWifiUrl: (map['captiveWifiUrl'] as String?)?.trim().isEmpty == true
          ? null
          : (map['captiveWifiUrl'] as String?),
      gatewayAddress: (map['gatewayAddress'] as String?)?.trim().isEmpty == true
          ? null
          : (map['gatewayAddress'] as String?),
      canExtendSession: map['canExtendSession'] as bool?,
      sessionExpiryTimeMillis: (map['sessionExpiryTimeMillis'] as num?)
          ?.toInt(),
    );
  }
}

class AndroidNetworkAssist {
  AndroidNetworkAssist._();

  static const MethodChannel _channel = MethodChannel(
    'preconnect/network_assist',
  );
  static const EventChannel _events = EventChannel(
    'preconnect/network_assist_events',
  );

  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<AndroidNetworkStatus?> getNetworkStatus() async {
    if (!isSupported) return null;
    try {
      final raw = await _channel.invokeMethod<dynamic>('getNetworkStatus');
      if (raw is Map<dynamic, dynamic>) {
        return AndroidNetworkStatus.fromMap(raw);
      }
    } catch (_) {}
    return null;
  }

  static Stream<AndroidNetworkStatus> get statusStream {
    if (!isSupported) {
      return const Stream<AndroidNetworkStatus>.empty();
    }
    return _events
        .receiveBroadcastStream()
        .where((event) => event is Map<dynamic, dynamic>)
        .map(
          (event) =>
              AndroidNetworkStatus.fromMap(event as Map<dynamic, dynamic>),
        );
  }

  static Future<String> addWifiSuggestion({
    required String ssid,
    required String password,
    required String securityType,
  }) async {
    if (!isSupported) return 'unsupported-platform';
    try {
      final raw = await _channel.invokeMethod<dynamic>('addWifiSuggestion', {
        'ssid': ssid,
        'password': password,
        'securityType': securityType,
      });
      if (raw is Map<dynamic, dynamic>) {
        return (raw['status'] as String?) ?? 'unknown';
      }
      return 'unknown';
    } catch (e) {
      return 'error:${e.runtimeType}';
    }
  }

  static Future<String> removeAllWifiSuggestions() async {
    if (!isSupported) return 'unsupported-platform';
    try {
      final raw = await _channel.invokeMethod<dynamic>(
        'removeAllWifiSuggestions',
      );
      if (raw is Map<dynamic, dynamic>) {
        return (raw['status'] as String?) ?? 'unknown';
      }
      return 'unknown';
    } catch (e) {
      return 'error:${e.runtimeType}';
    }
  }

  static Future<Map<String, dynamic>> getAndClearPostConnectionEvent() async {
    if (!isSupported) return const <String, dynamic>{'pending': false};
    try {
      final raw = await _channel.invokeMethod<dynamic>(
        'getAndClearPostConnectionEvent',
      );
      if (raw is Map<dynamic, dynamic>) {
        return raw.map((key, value) => MapEntry('$key', value));
      }
    } catch (_) {}
    return const <String, dynamic>{'pending': false};
  }
}
