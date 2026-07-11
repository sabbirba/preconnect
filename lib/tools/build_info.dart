import 'package:package_info_plus/package_info_plus.dart';

class BuildInfo {
  const BuildInfo._();

  static const String version = String.fromEnvironment('APP_VERSION');

  static const String buildNumber = String.fromEnvironment('APP_BUILD_NUMBER');

  static Future<String> displayVersion() async {
    final info = await _info();
    final cleanVersion = info.version.trim();
    final cleanBuild = info.buildNumber.trim();
    if (cleanVersion.isEmpty && cleanBuild.isEmpty) return 'App Version';
    if (cleanBuild.isEmpty) return 'v$cleanVersion';
    return 'v$cleanVersion ($cleanBuild)';
  }

  static Future<String> fullVersion() async {
    final info = await _info();
    final cleanVersion = info.version.trim();
    final cleanBuild = info.buildNumber.trim();
    if (cleanVersion.isEmpty) return cleanBuild;
    if (cleanBuild.isEmpty) return cleanVersion;
    return '$cleanVersion+$cleanBuild';
  }

  static Future<_BuildInfoData> _info() async {
    final definedVersion = version.trim();
    final definedBuildNumber = buildNumber.trim();
    if (definedVersion.isNotEmpty || definedBuildNumber.isNotEmpty) {
      return _BuildInfoData(
        version: definedVersion,
        buildNumber: definedBuildNumber,
      );
    }

    try {
      final packageInfo = await PackageInfo.fromPlatform();
      return _BuildInfoData(
        version: packageInfo.version.trim(),
        buildNumber: packageInfo.buildNumber.trim(),
      );
    } catch (_) {
      return const _BuildInfoData();
    }
  }
}

class _BuildInfoData {
  const _BuildInfoData({this.version = '', this.buildNumber = ''});

  final String version;
  final String buildNumber;
}
