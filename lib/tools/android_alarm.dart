import 'package:flutter/services.dart';
import 'package:preconnect/tools/platform_channels.dart';

abstract final class AndroidAlarm {
  static const MethodChannel _channel = MethodChannel(
    PlatformChannels.androidAlarm,
  );

  static Future<bool> set({
    required int hour,
    required int minute,
    required String message,
    List<int>? days,
  }) async {
    return await _channel.invokeMethod<bool>('setAlarm', {
          'hour': hour,
          'minute': minute,
          'message': message,
          'days': ?days,
        }) ??
        false;
  }
}
