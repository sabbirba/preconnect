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

class _ScanSchedulePageState extends State<ScanSchedulePage>
    with WidgetsBindingObserver {
  final MobileScannerController _controller = MobileScannerController(
    autoStart: false,
  );
  String? scannedValue;
  bool? _cameraGranted;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ensureCameraPermission();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    if (state == AppLifecycleState.resumed) {
      if (_cameraGranted == true && scannedValue == null) {
        _startScanner();
      }
      return;
    }
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _controller.stop();
    }
  }

  Future<void> _ensureCameraPermission({
    bool openSettingsOnDeny = false,
  }) async {
    if (kIsWeb) {
      if (mounted) setState(() => _cameraGranted = false);
      return;
    }
    final grantedByPlatform = defaultTargetPlatform == TargetPlatform.macOS;
    PermissionStatus requested = PermissionStatus.granted;
    if (!grantedByPlatform) {
      final status = await Permission.camera.status;
      requested = status.isGranted ? status : await Permission.camera.request();
    }
    if (!mounted) return;
    setState(() => _cameraGranted = requested.isGranted);
    if (requested.isGranted) {
      _startScanner();
    } else if (openSettingsOnDeny) {
      await openAppSettings();
    }
  }

  Future<void> _startScanner() async {
    if (!mounted || _cameraGranted != true || scannedValue != null) {
      return;
    }
    if (_controller.value.isRunning) {
      return;
    }
    try {
      await _controller.start();
    } catch (_) {}
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
    await _startScanner();
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
                          child: _cameraGranted == true
                              ? MobileScanner(
                                  controller: _controller,
                                  errorBuilder: (context, error) {
                                    final isPermissionError =
                                        error.errorCode ==
                                        MobileScannerErrorCode.permissionDenied;
                                    final message =
                                        (error.errorDetails?.message
                                                ?.trim()
                                                .isNotEmpty ??
                                            false)
                                        ? error.errorDetails!.message!
                                        : error.errorCode.message;
                                    return Container(
                                      color: Colors.black,
                                      alignment: Alignment.center,
                                      padding: const EdgeInsets.all(16),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(
                                            Icons.error_outline,
                                            color: Colors.white,
                                            size: 34,
                                          ),
                                          const SizedBox(height: 10),
                                          Text(
                                            message,
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 16,
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          if (isPermissionError)
                                            InkWell(
                                              onTap: openAppSettings,
                                              child: const Text(
                                                'Camera permission denied. Tap to open system settings.',
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w600,
                                                  decoration:
                                                      TextDecoration.underline,
                                                ),
                                              ),
                                            )
                                          else
                                            TextButton(
                                              onPressed: () =>
                                                  _ensureCameraPermission(
                                                    openSettingsOnDeny: true,
                                                  ),
                                              child: const Text(
                                                'Retry Camera',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    );
                                  },
                                  onDetect: (capture) async {
                                    if (scannedValue != null) return;
                                    if (capture.barcodes.isEmpty) return;
                                    final barcode = capture.barcodes.first;
                                    final value = barcode.rawValue;
                                    if (value == null || value.trim().isEmpty) {
                                      return;
                                    }
                                    if (!mounted) return;
                                    setState(() => scannedValue = value);
                                    await _saveScannedValue(value);
                                    await _controller.stop();
                                    RefreshBus.instance.notify(
                                      reason: 'scan_schedule',
                                    );
                                  },
                                )
                              : (_cameraGranted == null
                                    ? const Center(
                                        child: CircularProgressIndicator(),
                                      )
                                    : Center(
                                        child: TextButton(
                                          onPressed: () =>
                                              _ensureCameraPermission(
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
                                      )),
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
                              _startScanner();
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
