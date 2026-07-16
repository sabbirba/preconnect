import 'dart:async';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:preconnect/api/fcm.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/network_assist.dart';

class PermissionRequirement {
  final Permission permission;
  final String title;
  final String reason;
  final IconData icon;
  final bool androidOnly;
  final bool iosOnly;
  final int? minAndroidSdk;
  final bool isOptional;

  const PermissionRequirement({
    required this.permission,
    required this.title,
    required this.reason,
    required this.icon,
    this.androidOnly = false,
    this.iosOnly = false,
    this.minAndroidSdk,
    this.isOptional = false,
  });
}

class BracuPermissionHelper {
  static const List<PermissionRequirement> list = [
    PermissionRequirement(
      permission: Permission.locationWhenInUse,
      title: 'Location Services',
      reason: 'Detect B-LAN WiFi SSID.',
      icon: Icons.location_on_rounded,
      isOptional: true,
    ),
    PermissionRequirement(
      permission: Permission.nearbyWifiDevices,
      title: 'Nearby WiFi Devices',
      reason: 'Detect Printer Network IP',
      icon: Icons.wifi_find_rounded,
      androidOnly: true,
      minAndroidSdk: 33,
    ),
    PermissionRequirement(
      permission: Permission.camera,
      title: 'Camera Access',
      reason: 'Scan Friends QR Code.',
      icon: Icons.camera_alt_rounded,
    ),
    PermissionRequirement(
      permission: Permission.photos,
      title: 'Photo Library',
      reason: 'Pick Friends QR Image.',
      icon: Icons.photo_library_rounded,
      iosOnly: true,
    ),
    PermissionRequirement(
      permission: Permission.ignoreBatteryOptimizations,
      title: 'Battery Exemption',
      reason: 'Keep App Notifications Active.',
      icon: Icons.battery_charging_full_rounded,
      androidOnly: true,
    ),
    PermissionRequirement(
      permission: Permission.scheduleExactAlarm,
      title: 'Exact Alarms',
      reason: 'Keep Schedule Timing Precise.',
      icon: Icons.alarm_rounded,
      androidOnly: true,
      minAndroidSdk: 33,
      isOptional: true,
    ),
    PermissionRequirement(
      permission: Permission.accessNotificationPolicy,
      title: 'Do Not Disturb',
      reason: 'Automate Quiet Mode Schedule.',
      icon: Icons.do_not_disturb_on_rounded,
      androidOnly: true,
      isOptional: true,
    ),
    PermissionRequirement(
      permission: Permission.notification,
      title: 'Notifications',
      reason: 'Receive Schedule Alerts.',
      icon: Icons.notifications_active_rounded,
      minAndroidSdk: 33,
    ),
  ];

  static Future<void> checkAndRequestOnStartup(BuildContext context) async {
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    if (!context.mounted) return;
    int androidSdk = 0;
    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        final androidInfo = await DeviceInfoPlugin().androidInfo;
        androidSdk = androidInfo.version.sdkInt;
      } catch (_) {}
    }

    final pending = <PermissionRequirement>[];
    for (final req in list) {
      if (req.androidOnly && defaultTargetPlatform != TargetPlatform.android) {
        continue;
      }
      if (req.iosOnly && defaultTargetPlatform != TargetPlatform.iOS) {
        continue;
      }
      if (req.minAndroidSdk != null &&
          defaultTargetPlatform == TargetPlatform.android &&
          androidSdk < req.minAndroidSdk!) {
        continue;
      }

      if (req.isOptional) {
        continue;
      }
      final status = await req.permission.status;
      bool isOk = status.isGranted || status.isLimited;
      if (isOk && req.permission == Permission.locationWhenInUse) {
        final gpsOn = await AndroidNetworkAssist.isLocationServiceEnabled();
        if (!gpsOn) {
          isOk = false;
        }
      }

      if (!isOk) {
        pending.add(req);
      }
    }

    if (pending.isEmpty) return;

    if (!context.mounted) return;

    await showBracuBottomSheet<void>(
      context,
      title: 'Permissions Required',
      subtitle:
          'PreConnect needs the following permissions to function properly. Please grant them to continue.',
      initialChildSize: 0.52,
      builder: (sheetContext, textPrimary, textSecondary) {
        return _BracuPermissionBottomSheetContent(requirements: pending);
      },
    );

    unawaited(FCMService.instance.init());
  }
}

class _BracuPermissionBottomSheetContent extends StatefulWidget {
  final List<PermissionRequirement> requirements;

  const _BracuPermissionBottomSheetContent({required this.requirements});

  @override
  State<_BracuPermissionBottomSheetContent> createState() =>
      _BracuPermissionBottomSheetContentState();
}

class _BracuPermissionBottomSheetContentState
    extends State<_BracuPermissionBottomSheetContent>
    with WidgetsBindingObserver {
  late Map<Permission, PermissionStatus> _statuses;
  late Map<Permission, bool> _services;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _statuses = {
      for (final req in widget.requirements)
        req.permission: PermissionStatus.denied,
    };
    _services = {for (final req in widget.requirements) req.permission: true};
    _updateStatuses();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _updateStatuses();
    }
  }

  Future<void> _updateStatuses() async {
    final updatedStatuses = <Permission, PermissionStatus>{};
    final updatedServices = <Permission, bool>{};

    for (final req in widget.requirements) {
      final status = await req.permission.status;
      updatedStatuses[req.permission] = status;

      bool serviceOn = true;
      if (req.permission == Permission.locationWhenInUse) {
        serviceOn = await AndroidNetworkAssist.isLocationServiceEnabled();
      }
      updatedServices[req.permission] = serviceOn;
    }

    if (mounted) {
      setState(() {
        _statuses = updatedStatuses;
        _services = updatedServices;
      });
      _checkCompletion();
    }
  }

  void _checkCompletion() {
    final allGranted = widget.requirements.every((req) {
      final s = _statuses[req.permission];
      final serviceOn = _services[req.permission] ?? true;
      return s != null && (s.isGranted || s.isLimited) && serviceOn;
    });

    if (allGranted) {
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _grantPermission(PermissionRequirement req) async {
    final status = _statuses[req.permission] ?? PermissionStatus.denied;
    final isGranted = status.isGranted || status.isLimited;
    final serviceOn = _services[req.permission] ?? true;

    if (isGranted && !serviceOn) {
      if (req.permission == Permission.locationWhenInUse) {
        await AndroidNetworkAssist.openLocationSettings();
      }
      return;
    }

    if (status.isPermanentlyDenied) {
      await openAppSettings();
      return;
    }

    await req.permission.request();
    await _updateStatuses();
  }

  @override
  Widget build(BuildContext context) {
    final textPrimary = BracuPalette.textPrimary(context);
    final textSecondary = BracuPalette.textSecondary(context);
    final scrollController = bracuBottomSheetScrollController(context);

    return ListView.separated(
      controller: scrollController,
      padding: const EdgeInsets.only(bottom: 24, top: 8),
      itemCount: widget.requirements.length,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final req = widget.requirements[index];
        final status = _statuses[req.permission] ?? PermissionStatus.denied;
        final isGranted = status.isGranted || status.isLimited;
        final serviceOn = _services[req.permission] ?? true;
        final isCompleted = isGranted && serviceOn;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: isCompleted
                ? BracuPalette.primary.withValues(alpha: 0.08)
                : textSecondary.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isCompleted
                  ? BracuPalette.primary.withValues(alpha: 0.16)
                  : Colors.transparent,
              width: 0.8,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                req.icon,
                color: isCompleted ? BracuPalette.primary : textSecondary,
                size: 32,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      req.title,
                      style: TextStyle(
                        color: textPrimary,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      req.reason,
                      style: TextStyle(color: textSecondary, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              isCompleted
                  ? const Icon(
                      Icons.check_circle_rounded,
                      color: BracuPalette.primary,
                      size: 20,
                    )
                  : BracuActionButton(
                      label: !isGranted
                          ? (status.isPermanentlyDenied ? 'Settings' : 'Grant')
                          : 'Turn On',
                      outlined: true,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      onPressed: () => _grantPermission(req),
                    ),
            ],
          ),
        );
      },
    );
  }
}
