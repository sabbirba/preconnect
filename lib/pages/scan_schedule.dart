import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:permission_handler/permission_handler.dart';
import 'package:preconnect/api/friend_schedule_store.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/token_storage.dart';
import 'package:preconnect/tools/refresh_bus.dart';
import 'package:mobile_scanner/mobile_scanner.dart'
    if (dart.library.html) 'package:preconnect/tools/mobile_scanner_stub.dart';

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
    try {
      await _controller.start();
    } catch (_) {}
  }

  Future<void> _saveScannedValue(String value) async {
    await _store.upsertEncodedSchedule(value);
  }

  Future<void> _handleRefresh() async {
    setState(() => scannedValue = null);
    await _startScanner();
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
    return Scaffold(
      body: BracuPageScaffold(
        title: 'Scan Schedule',
        subtitle: 'QR Scan',
        icon: Icons.qr_code_scanner,
        body: _cameraGranted == null
            ? BracuRefreshList(
                onRefresh: _handleRefresh,
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                children: [
                  const SizedBox(height: 28),
                  BracuCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: double.infinity,
                          child: BracuActionButton(
                            onPressed: () => _ensureCameraPermission(
                              openSettingsOnDeny: true,
                            ),
                            label: 'Enable Camera',
                            isLoading: _isEnablingCamera,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              )
            : BracuRefreshList(
                onRefresh: _handleRefresh,
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                children: [
                  if (scannedValue == null)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        BracuCard(
                          child: AspectRatio(
                            aspectRatio: 1,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
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
                                              const SizedBox(height: 10),
                                              const Text(
                                                'Camera unavailable',
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 16,
                                                ),
                                              ),
                                              const SizedBox(height: 12),
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
                                        if (value == null ||
                                            value.trim().isEmpty) {
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
                                            child: _ScanScheduleLoadingState(),
                                          )
                                        : Center(
                                            child: TextButton(
                                              onPressed: () {
                                                if (kIsWeb) {
                                                  setState(
                                                    () => _cameraGranted = true,
                                                  );
                                                  _startScanner();
                                                  return;
                                                }
                                                _ensureCameraPermission(
                                                  openSettingsOnDeny: true,
                                                );
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
                                          )),
                            ),
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
                              BracuActionButton(
                                onPressed: _isRescanning
                                    ? null
                                    : _restartScanner,
                                icon: Icons.qr_code_scanner,
                                label: 'Scan Again',
                                isLoading: _isRescanning,
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
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
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
                                        color: BracuPalette.textSecondary(
                                          context,
                                        ),
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
    );
  }
}

class _ScanScheduleLoadingState extends StatelessWidget {
  const _ScanScheduleLoadingState();

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}
