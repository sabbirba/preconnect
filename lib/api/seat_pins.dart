import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:preconnect/api/fcm.dart';
import 'package:preconnect/tools/preconnect_constants.dart';
import 'package:preconnect/tools/token_storage.dart';

enum SeatPinResult {
  alertsOn,
  alertsOff,
  pinnedLocally,
  unpinned,
  permissionDenied,
  failed,
}

class SeatPins extends ChangeNotifier {
  SeatPins._();

  static final SeatPins instance = SeatPins._();
  static const String _scope = PreConnectPushConfig.seatStatusPinScope;

  final Set<String> _pins = <String>{};

  Set<String> get pins => Set<String>.unmodifiable(_pins);

  bool contains(int sectionId) => _pins.contains('$sectionId');

  Future<void> load() async {
    final loaded = await CoursePinStore.load(_scope);
    if (setEquals(loaded, _pins)) return;
    _pins
      ..clear()
      ..addAll(loaded);
    notifyListeners();
  }

  Future<SeatPinResult> toggle(
    int sectionId, {
    required String courseCode,
    required String sectionName,
  }) async {
    final key = '$sectionId';
    final willPin = !_pins.contains(key);
    _setPinned(key, willPin);
    try {
      await CoursePinStore.save(_scope, _pins);
    } catch (_) {
      _setPinned(key, !willPin);
      return SeatPinResult.failed;
    }

    final fcm = FCMService.instance;
    if (!fcm.isSupported) {
      return willPin ? SeatPinResult.pinnedLocally : SeatPinResult.unpinned;
    }
    final topic = PreConnectPushConfig.seatTopic(key);
    if (!willPin) {
      unawaited(fcm.unsubscribeFromTopic(topic));
      return SeatPinResult.alertsOff;
    }

    var permitted = true;
    try {
      permitted =
          await fcm.isNotificationPermissionGranted() ||
          await fcm.requestNotificationPermission();
    } catch (_) {
      permitted = false;
    }

    var subscribed = false;
    try {
      subscribed = await fcm.subscribeToTopic(topic);
    } catch (_) {
      subscribed = false;
    }
    if (!subscribed) {
      _setPinned(key, false);
      await CoursePinStore.save(_scope, _pins);
      return SeatPinResult.failed;
    }

    unawaited(fcm.sendConfirmationNotification(courseCode, sectionName));
    return permitted ? SeatPinResult.alertsOn : SeatPinResult.permissionDenied;
  }

  void _setPinned(String key, bool pinned) {
    final changed = pinned ? _pins.add(key) : _pins.remove(key);
    if (changed) notifyListeners();
  }
}

String seatPinMessage(
  SeatPinResult result, {
  required String courseCode,
  required String sectionName,
}) {
  final label = '$courseCode Section $sectionName';
  return switch (result) {
    SeatPinResult.alertsOn => '$label alerts enabled',
    SeatPinResult.alertsOff => '$label alerts disabled',
    SeatPinResult.pinnedLocally => '$label pinned locally',
    SeatPinResult.unpinned => '$label unpinned',
    SeatPinResult.permissionDenied =>
      'Notification permission is disabled. Enable it in Settings to receive push alerts.',
    SeatPinResult.failed =>
      'Failed to sync seat alert. Please check your internet connection.',
  };
}
