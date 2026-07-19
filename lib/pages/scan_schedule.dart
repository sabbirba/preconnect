import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:preconnect/api/friend_store.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/token_storage.dart';
import 'package:preconnect/tools/refresh_bus.dart';
import 'package:mobile_scanner/mobile_scanner.dart'
    if (dart.library.js_interop) 'package:preconnect/tools/scanner_stub.dart';
import 'package:preconnect/tools/clipboard_stub.dart'
    if (dart.library.js_interop) 'package:preconnect/tools/clipboard_web.dart';

class ScanSchedulePage extends StatefulWidget {
  const ScanSchedulePage({super.key});

  @override
  State<ScanSchedulePage> createState() => _ScanSchedulePageState();
}

class _ScanSchedulePageState extends State<ScanSchedulePage>
    with WidgetsBindingObserver {
  final FriendScheduleStore _store = FriendScheduleStore();
  final MobileScannerController _controller = MobileScannerController(
    autoStart: false,
  );
  String? scannedValue;
  bool? _cameraGranted;
  bool _isEnablingCamera = false;
  bool _isRescanning = false;

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
    if (_isEnablingCamera) return;
    setState(() => _isEnablingCamera = true);
    final granted = await PlatformPermissions.requestScannerCameraPermission();
    if (!mounted) return;
    setState(() => _cameraGranted = granted);
    if (granted) {
      _startScanner();
    } else if (openSettingsOnDeny) {
      await openAppSettings();
    }
    if (mounted) {
      setState(() => _isEnablingCamera = false);
    }
  }

  Future<void> _startScanner() async {
    if (!mounted || _cameraGranted != true || scannedValue != null) {
      return;
    }
    if (_controller.value.isRunning) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || _controller.value.isRunning) return;
      try {
        await _controller.start();
      } catch (_) {}
    });
  }

  Future<void> _saveScannedValue(String value) async {
    try {
      final decodedBase64 = base64.decode(value);
      final decodedGzip = GZipDecoder().decodeBytes(decodedBase64);
      final originalJson = utf8.decode(decodedGzip);
      final parsed = jsonDecode(originalJson);
      if (parsed is Map<String, dynamic> &&
          parsed['type'] == 'friend_schedules_export') {
        final schedules = parsed['schedules'];
        if (schedules is List) {
          for (final sched in schedules) {
            if (sched is String) {
              await _store.upsertEncodedSchedule(sched);
            }
          }
        }
        return;
      }
    } catch (_) {}
    await _store.upsertEncodedSchedule(value);
  }

  Future<void> _pasteCode() async {
    String? text;
    if (kIsWeb) {
      try {
        text = await readClipboardText();
      } catch (_) {}
    }
    if (text == null || text.trim().isEmpty) {
      try {
        final ClipboardData? data = await Clipboard.getData(
          Clipboard.kTextPlain,
        );
        text = data?.text;
      } catch (_) {}
    }

    if (text == null || text.trim().isEmpty) {
      if (!mounted) return;
      showAppSnackBar(context, 'Clipboard is empty');
      return;
    }
    final value = text.trim();
    if (!mounted) return;
    setState(() => scannedValue = value);
    await _saveScannedValue(value);
    try {
      await _controller.stop();
    } catch (_) {}
    RefreshBus.instance.notify(reason: 'scan_schedule');
  }

  Future<void> _restartScanner() async {
    if (_isRescanning) return;
    setState(() => _isRescanning = true);
    try {
      await _controller.stop();
      if (!mounted) return;
      setState(() => scannedValue = null);
      await _startScanner();
    } finally {
      if (mounted) {
        setState(() => _isRescanning = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_cameraGranted == null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Gap(8),
            BracuCard(
              child: SizedBox(
                width: double.infinity,
                child: BracuActionButton(
                  onPressed: () =>
                      _ensureCameraPermission(openSettingsOnDeny: true),
                  label: 'Enable Camera',
                  isLoading: _isEnablingCamera,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (scannedValue != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Gap(16),
            const Icon(
              Icons.check_circle_rounded,
              size: 72,
              color: BracuPalette.accent,
            ),
            const Gap(16),
            const Text(
              'Schedule Added!',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const Gap(6),
            Text(
              'You can scan another QR anytime.',
              textAlign: TextAlign.center,
              style: TextStyle(color: BracuPalette.textSecondary(context)),
            ),
            const Gap(24),
            BracuActionButton(
              onPressed: () {
                Navigator.of(context).maybePop();
              },
              icon: Icons.check_circle_rounded,
              label: 'Done',
              outlined: false,
              backgroundColor: BracuPalette.accent,
              foregroundColor: Colors.white,
            ),
            const Gap(12),
            BracuActionButton(
              onPressed: _isRescanning ? null : _restartScanner,
              icon: Icons.qr_code_scanner,
              label: 'Scan Another',
              outlined: true,
              isLoading: _isRescanning,
            ),
          ],
        ),
      );
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: AspectRatio(
                aspectRatio: 1,
                child: _cameraGranted == true
                    ? MobileScanner(
                        controller: _controller,
                        errorBuilder: (context, error) {
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
                                const Gap(10),
                                const Text(
                                  'Camera unavailable',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                  ),
                                ),
                                const Gap(12),
                                TextButton(
                                  onPressed: () => _ensureCameraPermission(
                                    openSettingsOnDeny: true,
                                  ),
                                  child: const Text(
                                    'Retry Camera',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
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
                          if (value == null || value.trim().isEmpty) return;
                          if (!mounted) return;
                          setState(() => scannedValue = value);
                          await _saveScannedValue(value);
                          await _controller.stop();
                          RefreshBus.instance.notify(reason: 'scan_schedule');
                        },
                      )
                    : Center(
                        child: TextButton(
                          onPressed: () {
                            if (kIsWeb) {
                              setState(() => _cameraGranted = true);
                              _startScanner();
                              return;
                            }
                            _ensureCameraPermission(openSettingsOnDeny: true);
                          },
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
            const Gap(16),
            BracuActionButton(
              onPressed: _pasteCode,
              icon: Icons.paste_rounded,
              label: 'Paste Code',
              outlined: true,
            ),
          ],
        ),
      ),
    );
  }
}
