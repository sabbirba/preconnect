import 'package:flutter/services.dart';
import 'package:preconnect/tools/platform_channels.dart';

class NativeFile {
  NativeFile._();

  static const MethodChannel _channel = MethodChannel(PlatformChannels.file);

  static Future<bool> open(String path) async {
    return await _channel.invokeMethod<bool>('open', <String, String>{
          'path': path,
        }) ??
        false;
  }
}
