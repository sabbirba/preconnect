import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/app_log.dart';
import 'package:preconnect/tools/app_paths.dart';
import 'package:preconnect/tools/network_assist.dart';
import 'package:share_plus/share_plus.dart';

class DeviceDiagnosticsPage extends StatefulWidget {
  const DeviceDiagnosticsPage({super.key});

  @override
  State<DeviceDiagnosticsPage> createState() => _DeviceDiagnosticsPageState();
}

class _DeviceDiagnosticsPageState extends State<DeviceDiagnosticsPage>
    with WidgetsBindingObserver {
  Map<String, String> _deviceInfo = <String, String>{};
  Map<String, String> _networkInfo = <String, String>{};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_forceRequestPermissions());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_forceRequestPermissions());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _forceRequestPermissions() async {
    if (!AndroidNetworkAssist.isSupported) {
      await _loadAll();
      return;
    }
    var status = await Permission.locationWhenInUse.status;
    if (status.isGranted) {
      final gpsEnabled = await AndroidNetworkAssist.isLocationServiceEnabled();
      if (!gpsEnabled) {
        await AndroidNetworkAssist.openLocationSettings();
        return;
      }
      await _loadAll();
      return;
    }

    status = await Permission.locationWhenInUse.request();
    if (status.isGranted) {
      final gpsEnabled = await AndroidNetworkAssist.isLocationServiceEnabled();
      if (!gpsEnabled) {
        await AndroidNetworkAssist.openLocationSettings();
        return;
      }
      await _loadAll();
      return;
    }

    await openAppSettings();
  }

  Future<void> _loadAll() async {
    if (mounted) {
      setState(() => _loading = true);
    }
    await _loadDeviceInfo();
    await _loadNetworkInfo();
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  Future<void> _loadDeviceInfo() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final deviceInfo = DeviceInfoPlugin();
      final timeZone = DateTime.now().timeZoneName;
      final timeZoneOffset = DateTime.now().timeZoneOffset.toString();
      final docsDir = await AppPaths.documentsDirectory();
      final tempDir = await AppPaths.temporaryDirectory();
      final Map<String, String> data = <String, String>{
        'App Name': packageInfo.appName,
        'Package Name': packageInfo.packageName,
        'App Version': packageInfo.version,
        'Build Number': packageInfo.buildNumber,
        'System Locale': Platform.localeName,
        'Time Zone': '$timeZone (Offset $timeZoneOffset)',
        'Dart runtime': Platform.version,
        'Documents Path': docsDir.path,
        'Temporary Path': tempDir.path,
      };

      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        data.addAll(<String, String>{
          'Platform': 'Android',
          'OS Version': androidInfo.version.release,
          'OS Codename': androidInfo.version.codename,
          'Base OS': androidInfo.version.baseOS ?? 'Unknown',
          'SDK Level': androidInfo.version.sdkInt.toString(),
          'Brand': androidInfo.brand,
          'Manufacturer': androidInfo.manufacturer,
          'Model': androidInfo.model,
          'Device ID': androidInfo.id,
          'Display Build': androidInfo.display,
          'Board': androidInfo.board,
          'Hardware': androidInfo.hardware,
          'Host': androidInfo.host,
          'Product': androidInfo.product,
          'CPU Architectures': androidInfo.supportedAbis.join(', '),
          'Bootloader': androidInfo.bootloader,
          'Fingerprint': androidInfo.fingerprint,
          'Security Patch': androidInfo.version.securityPatch ?? 'Unknown',
          'Type': androidInfo.type,
          'Tags': androidInfo.tags,
          'Physical Device': androidInfo.isPhysicalDevice ? 'Yes' : 'No',
        });
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        data.addAll(<String, String>{
          'Platform': 'iOS',
          'System Name': iosInfo.systemName,
          'OS Version': iosInfo.systemVersion,
          'Model': iosInfo.model,
          'Localized Model': iosInfo.localizedModel,
          'Device Name': iosInfo.name,
          'Vendor ID': iosInfo.identifierForVendor ?? 'Unknown',
          'UTS Machine': iosInfo.utsname.machine,
          'UTS Release': iosInfo.utsname.release,
          'UTS Sysname': iosInfo.utsname.sysname,
          'UTS Version': iosInfo.utsname.version,
          'Physical Device': iosInfo.isPhysicalDevice ? 'Yes' : 'No',
        });
      }
      if (mounted) {
        setState(() {
          _deviceInfo = data;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadNetworkInfo() async {
    final Map<String, String> netData = <String, String>{
      'Transport': 'Unknown',
      'Connected': 'Unknown',
      'Validated': 'Unknown',
      'Captive Portal': 'Unknown',
      'SSID': 'Unknown',
      'Gateway IP': 'Unknown',
      'Local IP': 'Unknown',
      'AP BSSID': 'Unknown',
      'Client MAC': 'Unknown',
    };
    try {
      if (AndroidNetworkAssist.isSupported) {
        final status = await AndroidNetworkAssist.getNetworkStatus();
        if (status != null) {
          netData['Transport'] = status.transport.toUpperCase();
          netData['Connected'] = status.connected ? 'Yes' : 'No';
          netData['Validated'] = status.validated ? 'Yes' : 'No';
          netData['Captive Portal'] = status.captive ? 'Yes' : 'No';
          netData['SSID'] = (status.ssid ?? 'Unknown').trim();
          netData['Gateway IP'] = status.gatewayAddress ?? 'Unknown';
          netData['Local IP'] = status.ipAddress ?? 'Unknown';
          netData['AP BSSID'] = status.apMac ?? 'Unknown';
          netData['Client MAC'] = status.clientMac ?? 'Unknown';
        }
      } else {
        netData['Transport'] = 'Supported on Android only';
      }
      if (mounted) {
        setState(() {
          _networkInfo = netData;
        });
      }
    } catch (_) {}
  }

  Future<void> _shareLogs() async {
    try {
      final file = await AppLog.getFile();
      if (await file.exists()) {
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(file.path)],
            text: 'PreConnect System Diagnostics',
          ),
        );
      }
    } catch (_) {}
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: Text(
              label,
              style: TextStyle(
                color: BracuPalette.textSecondary(context),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const Gap(10),
          Expanded(
            flex: 6,
            child: GestureDetector(
              onTap: () => copyToClipboard(context, value),
              child: Text(
                value,
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: BracuPalette.textPrimary(context),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDivider(bool isDark) {
    return Divider(
      height: 18,
      thickness: 1,
      color: BracuPalette.textSecondary(
        context,
      ).withValues(alpha: isDark ? 0.22 : 0.14),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final width = mq.size.width.toInt();
    final height = mq.size.height.toInt();
    final ratio = mq.devicePixelRatio;
    final textScale = mq.textScaler.scale(1.0);
    final padding = mq.padding;
    final orientation = mq.orientation.toString().split('.').last;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final List<Widget> items = [];

    if (!_loading) {
      items.addAll([
        _buildInfoRow('Device Model', _deviceInfo['Model'] ?? 'Unknown'),
        _buildDivider(isDark),
        _buildInfoRow(
          'Operating System',
          '${_deviceInfo['Platform']} (Version ${_deviceInfo['OS Version']})',
        ),
        _buildDivider(isDark),
        _buildInfoRow('Brand / Maker', _deviceInfo['Brand'] ?? 'Unknown'),
        _buildDivider(isDark),
        _buildInfoRow('SDK version', _deviceInfo['SDK Level'] ?? 'Unknown'),
        _buildDivider(isDark),
        _buildInfoRow(
          'Physical Hardware',
          _deviceInfo['Physical Device'] ?? 'Yes',
        ),
        _buildDivider(isDark),
        _buildInfoRow('Bracu Card ID', _deviceInfo['Device ID'] ?? 'Unknown'),
        _buildDivider(isDark),
        if (Platform.isAndroid && _deviceInfo['CPU Architectures'] != null) ...[
          _buildInfoRow('OS Codename', _deviceInfo['OS Codename'] ?? 'Unknown'),
          _buildDivider(isDark),
          _buildInfoRow('Base OS', _deviceInfo['Base OS'] ?? 'Unknown'),
          _buildDivider(isDark),
          _buildInfoRow('CPU Architectures', _deviceInfo['CPU Architectures']!),
          _buildDivider(isDark),
          _buildInfoRow('Security Patch level', _deviceInfo['Security Patch']!),
          _buildDivider(isDark),
          _buildInfoRow('Fingerprint Signature', _deviceInfo['Fingerprint']!),
          _buildDivider(isDark),
          _buildInfoRow('Device Host', _deviceInfo['Host'] ?? 'Unknown'),
          _buildDivider(isDark),
          _buildInfoRow('Device Product', _deviceInfo['Product'] ?? 'Unknown'),
          _buildDivider(isDark),
        ],
        _buildInfoRow(
          'Documents Path',
          _deviceInfo['Documents Path'] ?? 'Unknown',
        ),
        _buildDivider(isDark),
        _buildInfoRow(
          'Temporary Path',
          _deviceInfo['Temporary Path'] ?? 'Unknown',
        ),
        _buildDivider(isDark),
        _buildInfoRow('Resolution (logical)', '${width}x$height'),
        _buildDivider(isDark),
        _buildInfoRow('Device Pixel Ratio', ratio.toStringAsFixed(2)),
        _buildDivider(isDark),
        _buildInfoRow('Orientation state', orientation),
        _buildDivider(isDark),
        _buildInfoRow('Font Scale Factor', textScale.toStringAsFixed(2)),
        _buildDivider(isDark),
        _buildInfoRow(
          'Safe Area Insets',
          'Top: ${padding.top.toInt()}, Bottom: ${padding.bottom.toInt()}',
        ),
        _buildDivider(isDark),
        _buildInfoRow(
          'Active Connection',
          _networkInfo['Transport'] ?? 'Unknown',
        ),
        _buildDivider(isDark),
        _buildInfoRow('SSID name', _networkInfo['SSID'] ?? 'Unknown'),
        _buildDivider(isDark),
        _buildInfoRow(
          'Gateway IP Address',
          _networkInfo['Gateway IP'] ?? 'Unknown',
        ),
        _buildDivider(isDark),
        _buildInfoRow(
          'Local IP Address',
          _networkInfo['Local IP'] ?? 'Unknown',
        ),
        _buildDivider(isDark),
        _buildInfoRow(
          'Access Point BSSID MAC',
          _networkInfo['AP BSSID'] ?? 'Unknown',
        ),
        _buildDivider(isDark),
        _buildInfoRow(
          'Internet Connectivity',
          _networkInfo['Validated'] == 'Yes' ? 'Connected' : 'Portal / Offline',
        ),
        _buildDivider(isDark),
        _buildInfoRow(
          'Application Name',
          _deviceInfo['App Name'] ?? 'PreConnect',
        ),
        _buildDivider(isDark),
        _buildInfoRow(
          'Release Version',
          '${_deviceInfo['App Version']} (${_deviceInfo['Build Number']})',
        ),
        _buildDivider(isDark),
        _buildInfoRow(
          'Package Name',
          _deviceInfo['Package Name'] ?? 'com.sabbirba.preconnect',
        ),
        _buildDivider(isDark),
        _buildInfoRow('System Locale', _deviceInfo['System Locale'] ?? 'en_US'),
        _buildDivider(isDark),
        _buildInfoRow('Local Time Zone', _deviceInfo['Time Zone'] ?? 'UTC'),
        const Gap(24),
        BracuActionBannerCard(
          icon: Icons.bug_report_outlined,
          title: 'Export Debug Logs',
          subtitle: 'Share diagnostic logs with developers',
          showTrailingIcon: true,
          onTap: _shareLogs,
        ),
      ]);
    }

    return BracuPageScaffold(
      title: 'Diagnostics',
      subtitle: 'System & Logs',
      icon: Icons.developer_board_rounded,
      actions: [
        BracuRefreshButton(
          onPressed: () {
            if (mounted) {
              setState(() => _loading = true);
            }
            unawaited(_forceRequestPermissions());
          },
          isLoading: _loading,
        ),
      ],
      body: _loading
          ? const Center(child: BracuLoading())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
              children: items,
            ),
    );
  }
}

class DeviceDiagnosticsButton extends StatelessWidget {
  const DeviceDiagnosticsButton({super.key});

  @override
  Widget build(BuildContext context) {
    return BracuActionBannerCard(
      icon: Icons.developer_board_rounded,
      title: 'Device Diagnostics',
      subtitle: 'View system specs and debug logs',
      showTrailingIcon: true,
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => const DeviceDiagnosticsPage(),
            settings: const RouteSettings(name: '/diagnostics'),
          ),
        );
      },
    );
  }
}
