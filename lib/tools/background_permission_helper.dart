import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum BackgroundPermissionStatus { allowed, denied, restricted, unknown }

class BackgroundPermissionHelper {
  BackgroundPermissionHelper._();

  static const MethodChannel _channel = MethodChannel(
    'preconnect/background_permission',
  );

  static Future<BackgroundPermissionStatus> getStatus() async {
    if (kIsWeb) return BackgroundPermissionStatus.allowed;
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        final ignored = await _channel.invokeMethod<bool>(
          'isBatteryOptimizationIgnored',
        );
        if (ignored == true) {
          return BackgroundPermissionStatus.allowed;
        } else {
          return BackgroundPermissionStatus.denied;
        }
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        final statusStr = await _channel.invokeMethod<String>(
          'getBackgroundRefreshStatus',
        );
        switch (statusStr) {
          case 'allowed':
            return BackgroundPermissionStatus.allowed;
          case 'denied':
            return BackgroundPermissionStatus.denied;
          case 'restricted':
            return BackgroundPermissionStatus.restricted;
          default:
            return BackgroundPermissionStatus.unknown;
        }
      }
    } catch (_) {}
    return BackgroundPermissionStatus.allowed;
  }

  static Future<bool> requestExemption() async {
    if (kIsWeb) return true;
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        return await _channel.invokeMethod<bool>(
              'requestIgnoreBatteryOptimization',
            ) ??
            false;
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        return await _channel.invokeMethod<bool>('openBackgroundSettings') ??
            false;
      }
    } catch (_) {}
    return false;
  }

  static Future<void> checkAndShowPrompt() async {
    if (kIsWeb) return;
    if (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS) {
      return;
    }

    final status = await getStatus();
    if (status != BackgroundPermissionStatus.allowed) {
      await requestExemption();
    }
  }
}
