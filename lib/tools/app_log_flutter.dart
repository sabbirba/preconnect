import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'app_log.dart';

class AppLogFlutter {
  AppLogFlutter._();

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
      await AppLog.write('System Info -> $infoStr');
    } catch (e) {
      await AppLog.write('Failed to log device info: $e');
    }
  }
}
