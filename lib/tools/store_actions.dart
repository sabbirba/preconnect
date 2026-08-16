import 'dart:async';

import 'package:flutter/services.dart';
import 'package:preconnect/tools/platform_channels.dart';

class StoreActions {
  StoreActions._();

  static const MethodChannel _storeChannel = MethodChannel(
    PlatformChannels.store,
  );
  static const MethodChannel _updateChannel = MethodChannel(
    PlatformChannels.appUpdate,
  );
  static const EventChannel _updateEvents = EventChannel(
    PlatformChannels.appUpdateEvents,
  );

  static Future<bool> isReviewAvailable() async {
    return await _storeChannel.invokeMethod<bool>('isReviewAvailable') ?? false;
  }

  static Future<bool> requestReview() async {
    return await _storeChannel.invokeMethod<bool>('requestReview') ?? false;
  }

  static Future<Map<String, dynamic>> checkForUpdate() async {
    final value = await _updateChannel.invokeMapMethod<String, dynamic>(
      'checkForUpdate',
    );
    return value ?? const <String, dynamic>{};
  }

  static Future<int?> startUpdate({required bool immediate}) {
    return _updateChannel.invokeMethod<int>('startUpdate', <String, Object?>{
      'immediate': immediate,
    });
  }

  static Future<void> completeUpdate() {
    return _updateChannel.invokeMethod<void>('completeUpdate');
  }

  static Stream<Map<String, dynamic>> get updateEvents => _updateEvents
      .receiveBroadcastStream()
      .map((value) => Map<String, dynamic>.from(value as Map));
}

abstract final class StoreUpdateStatus {
  static const int available = 2;
  static const int inProgress = 3;
  static const int downloaded = 11;
  static const int success = 0;
}
