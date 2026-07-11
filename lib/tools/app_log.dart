import 'dart:io';
import 'package:flutter/material.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'app_paths.dart';

class AppLog {
  AppLog._();

  static File? _file;

  static Future<File> getFile() async {
    if (_file != null) return _file!;
    final dir = await AppPaths.documentsDirectory();
    _file = File('${dir.path}/preconnect_debug_logs.txt');
    return _file!;
  }

  static Future<void> write(String message) async {
    try {
      final file = await getFile();
      if (await file.exists()) {
        final size = await file.length();
        if (size > 10 * 1024 * 1024) {
          await file.writeAsString('');
        }
      }
      final timestamp = DateTime.now().toIso8601String();
      await file.writeAsString(
        '[$timestamp] $message\n',
        mode: FileMode.append,
      );
    } catch (_) {}
  }

  static Future<void> logDeviceInfo() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final deviceInfo = DeviceInfoPlugin();
      final Map<String, dynamic> data = <String, dynamic>{
        'AppName': packageInfo.appName,
        'PackageName': packageInfo.packageName,
        'Version': packageInfo.version,
        'BuildNumber': packageInfo.buildNumber,
      };

      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        data.addAll(<String, dynamic>{
          'Platform': 'Android',
          'OSVersion': androidInfo.version.release,
          'SDKInt': androidInfo.version.sdkInt,
          'Brand': androidInfo.brand,
          'Manufacturer': androidInfo.manufacturer,
          'Model': androidInfo.model,
          'Device': androidInfo.device,
          'Hardware': androidInfo.hardware,
          'IsPhysicalDevice': androidInfo.isPhysicalDevice,
        });
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        data.addAll(<String, dynamic>{
          'Platform': 'iOS',
          'OSName': iosInfo.name,
          'SystemName': iosInfo.systemName,
          'SystemVersion': iosInfo.systemVersion,
          'Model': iosInfo.model,
          'LocalizedModel': iosInfo.localizedModel,
          'IsPhysicalDevice': iosInfo.isPhysicalDevice,
        });
      } else if (Platform.isMacOS) {
        final macInfo = await deviceInfo.macOsInfo;
        data.addAll(<String, dynamic>{
          'Platform': 'macOS',
          'OSVersion': macInfo.osRelease,
          'Model': macInfo.model,
          'KernelVersion': macInfo.kernelVersion,
        });
      }

      final infoStr = data.entries
          .map((e) => '${e.key}: ${e.value}')
          .join(', ');
      await write('System Info -> $infoStr');
    } catch (e) {
      await write('Failed to log device info: $e');
    }
  }
}

class AppLogNavigatorObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    AppLog.write(
      'Navigation Push: ${route.settings.name} (from: ${previousRoute?.settings.name})',
    );
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    AppLog.write(
      'Navigation Pop: ${route.settings.name} (to: ${previousRoute?.settings.name})',
    );
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    AppLog.write(
      'Navigation Replace: ${newRoute?.settings.name} (replaced: ${oldRoute?.settings.name})',
    );
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didRemove(route, previousRoute);
    AppLog.write('Navigation Remove: ${route.settings.name}');
  }
}
