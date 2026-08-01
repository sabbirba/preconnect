import 'dart:io';
import 'package:flutter/services.dart';
import 'package:preconnect/tools/platform_channels.dart';
import 'package:url_launcher/url_launcher.dart';

class NativeFile {
  NativeFile._();

  static const MethodChannel _channel = MethodChannel(PlatformChannels.file);

  static Future<bool> open(String path) async {
    try {
      final opened = await _channel.invokeMethod<bool>('open', <String, String>{
        'path': path,
      });
      if (opened == true) return true;
    } on PlatformException {
      return _openFileUri(path);
    } on MissingPluginException {
      return _openFileUri(path);
    }

    return _openFileUri(path);
  }

  static Future<bool> _openFileUri(String path) async {
    if (Platform.isAndroid) return false;
    try {
      return launchUrl(Uri.file(path), mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }
}
