import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/app_log.dart';
import 'package:preconnect/tools/app_paths.dart';
import 'package:preconnect/tools/app_storage.dart';
import 'package:preconnect/tools/network_assist.dart';
import 'package:preconnect/tools/storage_keys.dart';
import 'package:share_plus/share_plus.dart';

class DeviceDiagnosticsPage extends StatefulWidget {
  const DeviceDiagnosticsPage({super.key});

  @override
  State<DeviceDiagnosticsPage> createState() => _DeviceDiagnosticsPageState();
}

class _DeviceDiagnosticsPageState extends State<DeviceDiagnosticsPage> {
  Map<String, String> _deviceInfo = <String, String>{};
  Map<String, String> _networkInfo = <String, String>{};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_loadAll());
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
      final Map<String, String> data = <String, String>{};

      void put(String key, String? val) {
        if (val != null) {
          final trimmed = val.trim();
          if (trimmed.isNotEmpty &&
              trimmed != 'Unknown' &&
              trimmed != 'unknown') {
            data[key] = trimmed;
          }
        }
      }

      put('App Name', packageInfo.appName);
      put('Package Name', packageInfo.packageName);
      put('App Version', packageInfo.version);
      put('Build Number', packageInfo.buildNumber);
      put('System Locale', kIsWeb ? null : Platform.localeName);
      put('Time Zone', '$timeZone (Offset $timeZoneOffset)');
      put('Documents Path', docsDir.path);
      put('Temporary Path', tempDir.path);

      if (kIsWeb) {
        final webInfo = await deviceInfo.webBrowserInfo;
        put('Platform', 'Web Browser');
        put('Browser', webInfo.browserName.name);
        put('User Agent', webInfo.userAgent);
        put('Language', webInfo.language);
        put('Platform OS', webInfo.platform);
        put('Hardware Concurrency', webInfo.hardwareConcurrency?.toString());
        put('Device Memory (GB)', webInfo.deviceMemory?.toString());
      } else if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        put('Platform', 'Android');
        put('OS Version', androidInfo.version.release);
        put('OS Codename', androidInfo.version.codename);
        put('Base OS', androidInfo.version.baseOS);
        put('SDK Level', androidInfo.version.sdkInt.toString());
        put('Brand', androidInfo.brand);
        put('Manufacturer', androidInfo.manufacturer);
        put('Model', androidInfo.model);
        put('Device ID', androidInfo.id);
        put('Display Build', androidInfo.display);
        put('Board', androidInfo.board);
        put('Hardware', androidInfo.hardware);
        put('Host', androidInfo.host);
        put('Product', androidInfo.product);
        if (androidInfo.supportedAbis.isNotEmpty) {
          put('CPU Architectures', androidInfo.supportedAbis.join(', '));
        }
        put('Bootloader', androidInfo.bootloader);
        put('Fingerprint', androidInfo.fingerprint);
        put('Security Patch', androidInfo.version.securityPatch);
        put('Type', androidInfo.type);
        put('Tags', androidInfo.tags);
        put('Physical Device', androidInfo.isPhysicalDevice ? 'Yes' : 'No');
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        put('Platform', 'iOS');
        put('System Name', iosInfo.systemName);
        put('OS Version', iosInfo.systemVersion);
        put('Model', iosInfo.model);
        put('Localized Model', iosInfo.localizedModel);
        put('Device Name', iosInfo.name);
        put('Vendor ID', iosInfo.identifierForVendor);
        put('UTS Machine', iosInfo.utsname.machine);
        put('UTS Release', iosInfo.utsname.release);
        put('UTS Sysname', iosInfo.utsname.sysname);
        put('UTS Version', iosInfo.utsname.version);
        put('Physical Device', iosInfo.isPhysicalDevice ? 'Yes' : 'No');
      } else if (Platform.isMacOS) {
        final macosInfo = await deviceInfo.macOsInfo;
        put('Platform', 'macOS');
        put('Computer Name', macosInfo.computerName);
        put('Host Name', macosInfo.hostName);
        put('Arch', macosInfo.arch);
        put('Model', macosInfo.model);
        put('OS Release', macosInfo.osRelease);
        put('Kernel Version', macosInfo.kernelVersion);
        put('Active CPUs', macosInfo.activeCPUs.toString());
        put('Memory Size (Bytes)', macosInfo.memorySize.toString());
        put('CPU Frequency', macosInfo.cpuFrequency.toString());
        put('System GUID', macosInfo.systemGUID);
      }
      if (mounted) {
        setState(() {
          _deviceInfo = data;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadNetworkInfo() async {
    final Map<String, String> netData = <String, String>{};

    void putNet(String key, String? val) {
      if (val != null) {
        final trimmed = val.trim();
        if (trimmed.isNotEmpty &&
            trimmed != 'Unknown' &&
            trimmed != 'unknown' &&
            trimmed != 'Android only') {
          netData[key] = trimmed;
        }
      }
    }

    try {
      if (AndroidNetworkAssist.isSupported) {
        final status = await AndroidNetworkAssist.getNetworkStatus();
        if (status != null) {
          putNet('Transport', status.transport.toUpperCase());
          putNet('Connected', status.connected ? 'Yes' : 'No');
          putNet('Validated', status.validated ? 'Yes' : 'No');
          putNet('Captive Portal', status.captive ? 'Yes' : 'No');
          putNet('SSID', status.ssid);
          putNet('Gateway IP', status.gatewayAddress);
          putNet('Local IP', status.ipAddress);
          putNet('AP BSSID', status.apMac);
          putNet('Client MAC', status.clientMac);
        }
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
      final studentId =
          (await AppStorage.instance.getString(
            StorageKeys.studentId,
          ))?.trim() ??
          '';
      final fileName = studentId.isNotEmpty
          ? '${studentId}_diagnostics.txt'
          : 'diagnostics.txt';
      final summary = StringBuffer();
      summary.writeln('=== PreConnect System Diagnostics ===');
      summary.writeln(
        'Generated on: ${DateTime.now().toUtc().toIso8601String()}',
      );
      if (studentId.isNotEmpty) {
        summary.writeln('Student ID: $studentId');
      }
      summary.writeln();
      summary.writeln('--- Device Info ---');
      for (final entry in _deviceInfo.entries) {
        summary.writeln('${entry.key}: ${entry.value}');
      }
      summary.writeln();
      if (_networkInfo.isNotEmpty) {
        summary.writeln('--- Network Info ---');
        for (final entry in _networkInfo.entries) {
          summary.writeln('${entry.key}: ${entry.value}');
        }
        summary.writeln();
      }
      summary.writeln('--- Debug Logs ---');
      final logs = await AppLog.read();
      summary.writeln(logs.trim().isEmpty ? 'No logs recorded.' : logs.trim());

      final content = summary.toString();
      if (kIsWeb) {
        final bytes = Uint8List.fromList(utf8.encode(content));
        final xfile = XFile.fromData(
          bytes,
          mimeType: 'text/plain',
          name: fileName,
        );
        await SharePlus.instance.share(ShareParams(files: [xfile]));
      } else {
        final tempDir = await AppPaths.temporaryDirectory();
        final exportFile = File('${tempDir.path}/$fileName');
        await exportFile.writeAsString(content, flush: true);
        await SharePlus.instance.share(
          ShareParams(
            files: [
              XFile(exportFile.path, mimeType: 'text/plain', name: fileName),
            ],
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
          const Gap(12),
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
    final size = MediaQuery.sizeOf(context);
    final width = size.width.toInt();
    final height = size.height.toInt();
    final ratio = MediaQuery.devicePixelRatioOf(context);
    final textScale = MediaQuery.textScalerOf(context).scale(1.0);
    final padding = MediaQuery.paddingOf(context);
    final orientation = MediaQuery.orientationOf(
      context,
    ).toString().split('.').last;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final List<Widget> items = [];

    if (!_loading) {
      void addRow(String label, String? value) {
        if (value != null) {
          final trimmed = value.trim();
          if (trimmed.isNotEmpty &&
              trimmed != 'Unknown' &&
              trimmed != 'unknown') {
            if (items.isNotEmpty) {
              items.add(_buildDivider(isDark));
            }
            items.add(_buildInfoRow(label, trimmed));
          }
        }
      }

      addRow('Device Model', _deviceInfo['Model']);
      if (_deviceInfo['Platform'] != null &&
          _deviceInfo['OS Version'] != null) {
        addRow(
          'Operating System',
          '${_deviceInfo['Platform']} (Version ${_deviceInfo['OS Version']})',
        );
      } else {
        addRow('Operating System', _deviceInfo['Platform']);
      }
      addRow('Brand / Maker', _deviceInfo['Brand']);
      addRow('SDK version', _deviceInfo['SDK Level']);
      addRow('Physical Hardware', _deviceInfo['Physical Device']);
      addRow('Device Build ID', _deviceInfo['Device ID']);
      addRow('OS Codename', _deviceInfo['OS Codename']);
      addRow('Base OS', _deviceInfo['Base OS']);
      addRow('CPU Architectures', _deviceInfo['CPU Architectures']);
      addRow('Security Patch level', _deviceInfo['Security Patch']);
      addRow('Fingerprint Signature', _deviceInfo['Fingerprint']);
      addRow('Device Host', _deviceInfo['Host']);
      addRow('Device Product', _deviceInfo['Product']);
      addRow('Documents Path', _deviceInfo['Documents Path']);
      addRow('Temporary Path', _deviceInfo['Temporary Path']);
      addRow('Resolution (logical)', '${width}x$height');
      addRow('Device Pixel Ratio', ratio.toStringAsFixed(2));
      addRow('Orientation state', orientation);
      addRow('Font Scale Factor', textScale.toStringAsFixed(2));
      addRow(
        'Safe Area Insets',
        'Top: ${padding.top.toInt()}, Bottom: ${padding.bottom.toInt()}',
      );
      addRow('Active Connection', _networkInfo['Transport']);
      addRow('SSID name', _networkInfo['SSID']);
      addRow('Gateway IP Address', _networkInfo['Gateway IP']);
      addRow('Local IP Address', _networkInfo['Local IP']);
      addRow('Access Point BSSID MAC', _networkInfo['AP BSSID']);
      addRow('Client MAC Address', _networkInfo['Client MAC']);
      if (_networkInfo['Validated'] != null) {
        addRow(
          'Internet Connectivity',
          _networkInfo['Validated'] == 'Yes' ? 'Connected' : 'Portal / Offline',
        );
      }
      addRow('Application Name', _deviceInfo['App Name']);
      if (_deviceInfo['App Version'] != null) {
        final buildNum = _deviceInfo['Build Number'];
        final versionStr = buildNum != null && buildNum.isNotEmpty
            ? '${_deviceInfo['App Version']} ($buildNum)'
            : _deviceInfo['App Version']!;
        addRow('Release Version', versionStr);
      }
      addRow('Package Name', _deviceInfo['Package Name']);
      addRow('System Locale', _deviceInfo['System Locale']);
      addRow('Local Time Zone', _deviceInfo['Time Zone']);

      items.add(const Gap(24));
      items.add(
        BracuActionBannerCard(
          icon: Icons.bug_report_outlined,
          title: 'Export Debug Logs',
          subtitle: 'Share diagnostic logs with developers',
          showTrailingIcon: true,
          onTap: _shareLogs,
        ),
      );
    }

    return BracuPageScaffold(
      title: 'Diagnostics',
      subtitle: 'System & Logs',
      icon: Icons.developer_board_rounded,
      actions: [
        BracuRefreshButton(
          onPressed: () {
            unawaited(_loadAll());
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
