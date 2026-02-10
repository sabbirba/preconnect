import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/refresh_bus.dart';

class ScanSchedulePage extends StatefulWidget {
  const ScanSchedulePage({super.key});

  @override
  State<ScanSchedulePage> createState() => _ScanSchedulePageState();
}

class _ScanSchedulePageState extends State<ScanSchedulePage> {
  final MobileScannerController _controller = MobileScannerController();
  String? scannedValue;
  bool _cameraGranted = true;

  @override
  void initState() {
    super.initState();
    _ensureCameraPermission();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _ensureCameraPermission({bool openSettingsOnDeny = false}) async {
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      setState(() => _cameraGranted = true);
      return;
    }
    if (kIsWeb) {
      setState(() => _cameraGranted = false);
      return;
    }
    final status = await Permission.camera.status;
    if (!mounted) return;
    if (openSettingsOnDeny &&
        (status.isPermanentlyDenied || status.isRestricted)) {
      setState(() => _cameraGranted = false);
      await openAppSettings();
      return;
    }
    final requested = await Permission.camera.request();
    if (!mounted) return;
    setState(() => _cameraGranted = requested.isGranted);
    if (!requested.isGranted && openSettingsOnDeny) {
      await openAppSettings();
    }
  }

  Future<void> _saveScannedValue(String value) async {
    final prefs = await SharedPreferences.getInstance();

    List<String> currentList = prefs.getStringList("friendSchedules") ?? [];

    if (!currentList.contains(value)) {
      final scannedId = _extractFriendId(value);
      if (scannedId != null && scannedId.trim().isNotEmpty) {
        currentList = currentList.where((entry) {
          final existingId = _extractFriendId(entry);
          if (existingId == null) return true;
          return existingId.trim() != scannedId.trim();
        }).toList();
      }
      currentList.add(value);
      await prefs.setStringList("friendSchedules", currentList);
    }

    await prefs.setStringList("friendSchedules", currentList);
  }

  String? _extractFriendId(String base64Data) {
    try {
      final Uint8List decodeBase64Json = base64.decode(base64Data);
      final List<int> decodeGzipJson = GZipDecoder().decodeBytes(
        decodeBase64Json,
      );
      final String originalJson = utf8.decode(decodeGzipJson);
      final parsed = jsonDecode(originalJson);
      if (parsed is Map<String, dynamic>) {
        return parsed['id']?.toString();
      }
    } catch (_) {}
    return null;
  }

  Future<void> _handleRefresh() async {
    setState(() => scannedValue = null);
    _controller.start();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: BracuPageScaffold(
        title: 'Scan Schedule',
        subtitle: 'Import From QR',
        icon: Icons.qr_code_scanner,
        body: RefreshIndicator(
          onRefresh: _handleRefresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              if (scannedValue == null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const BracuSectionTitle(title: 'Scan QR Code'),
                    const SizedBox(height: 10),
                    BracuCard(
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: _cameraGranted
                              ? MobileScanner(
                                  controller: _controller,
                                  onDetect: (capture) async {
                                    if (capture.barcodes.isEmpty) return;
                                    final barcode = capture.barcodes.first;
                                    final value = barcode.rawValue;
                                    if (value == null || value.trim().isEmpty) {
                                      return;
                                    }
                                    setState(() {
                                      scannedValue = value;
                                    });
                                    await _saveScannedValue(value);
                                    _controller.stop();
                                    RefreshBus.instance
                                        .notify(reason: 'scan_schedule');
                                  },
                                )
                              : Center(
                                  child: TextButton(
                                    onPressed: () => _ensureCameraPermission(
                                      openSettingsOnDeny: true,
                                    ),
                                    child: Text(
                                      'Tap to enable camera',
                                      style: TextStyle(
                                        color: BracuPalette.primary,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    BracuCard(
                      child: Row(
                        children: [
                          const Icon(
                            Icons.info_outline,
                            color: BracuPalette.primary,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Align the QR code within the frame to import your friend’s schedule.',
                              style: TextStyle(
                                color: BracuPalette.textSecondary(context),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                )
              else
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    BracuCard(
                      child: Column(
                        children: [
                          const Icon(
                            Icons.check_circle,
                            size: 72,
                            color: BracuPalette.accent,
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Schedule Added!',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'You can scan another QR anytime.',
                            style: TextStyle(
                              color: BracuPalette.textSecondary(context),
                            ),
                          ),
                          const SizedBox(height: 16),
                          InkWell(
                            onTap: () {
                              setState(() => scannedValue = null);
                              _controller.start();
                            },
                            borderRadius: BorderRadius.circular(18),
                            child: BracuCard(
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: BracuPalette.primary.withValues(
                                        alpha: 0.12,
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Icon(
                                      Icons.qr_code_scanner,
                                      color: BracuPalette.primary,
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  const Expanded(
                                    child: Text(
                                      'Scan Again',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  Icon(
                                    Icons.arrow_forward,
                                    color: BracuPalette.textSecondary(context),
                                    size: 18,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          InkWell(
                            onTap: () {
                              Navigator.of(context).maybePop();
                            },
                            borderRadius: BorderRadius.circular(18),
                            child: BracuCard(
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: BracuPalette.accent.withValues(
                                        alpha: 0.12,
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Icon(
                                      Icons.check_rounded,
                                      color: BracuPalette.accent,
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  const Expanded(
                                    child: Text(
                                      'Done',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  Icon(
                                    Icons.arrow_forward,
                                    color: BracuPalette.textSecondary(context),
                                    size: 18,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}
