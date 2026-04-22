import 'package:flutter/services.dart';

class WidgetSnapshotBridge {
  WidgetSnapshotBridge._();

  static const MethodChannel _channel = MethodChannel(
    'preconnect/widget_snapshot',
  );

  static Future<void> setAlarmSnapshot({
    required String label,
    required DateTime fireDate,
  }) async {
    await _channel.invokeMethod('setAlarmSnapshot', {
      'label': label,
      'fireDateMillis': fireDate.millisecondsSinceEpoch.toDouble(),
    });
  }

  static Future<void> clearAlarmSnapshot() async {
    await _channel.invokeMethod('clearAlarmSnapshot');
  }
}
