import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:preconnect/api/friend_store.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/token_storage.dart';
import 'package:flutter_zxing/flutter_zxing.dart'
    if (dart.library.js_interop) 'package:preconnect/tools/scanner_stub.dart';
import 'package:preconnect/tools/clipboard_stub.dart'
    if (dart.library.js_interop) 'package:preconnect/tools/clipboard_web.dart';

class ScanSchedulePage extends StatefulWidget {
  const ScanSchedulePage({super.key, required this.onCompleted});

  final VoidCallback onCompleted;

  @override
  State<ScanSchedulePage> createState() => _ScanSchedulePageState();
}

class _ScanSchedulePageState extends State<ScanSchedulePage> {
  final FriendScheduleStore _store = FriendScheduleStore();
  String? scannedValue;
  bool? _cameraGranted;
  bool _cameraFailed = false;
  bool _isEnablingCamera = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _ensureCameraPermission();
  }

  Future<void> _ensureCameraPermission({
    bool openSettingsOnDeny = false,
  }) async {
    if (_isEnablingCamera) return;
    setState(() => _isEnablingCamera = true);
    final granted = await PlatformPermissions.requestScannerCameraPermission();
    if (!mounted) return;
    setState(() => _cameraGranted = granted);
    if (!granted && openSettingsOnDeny) {
      await openAppSettings();
    }
    if (mounted) {
      setState(() => _isEnablingCamera = false);
    }
  }

  Future<void> _acceptScannedValue(String value) async {
    if (_isSaving || scannedValue != null) return;
    _isSaving = true;
    try {
      await _store.importPayload(value);
      if (!mounted) return;
      setState(() => scannedValue = value);
    } on FormatException {
      if (!mounted) return;
      showAppSnackBar(context, 'Invalid friend schedule QR code');
    } catch (_) {
      if (!mounted) return;
      showAppSnackBar(context, 'Could not save friend schedule');
    } finally {
      _isSaving = false;
    }
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
    await _acceptScannedValue(value);
  }

  void _restartScanner() {
    setState(() {
      scannedValue = null;
      _cameraFailed = false;
    });
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
              onPressed: widget.onCompleted,
              icon: Icons.check_circle_rounded,
              label: 'Done',
              outlined: false,
              backgroundColor: BracuPalette.accent,
              foregroundColor: Colors.white,
            ),
            const Gap(12),
            BracuActionButton(
              onPressed: _restartScanner,
              icon: Icons.qr_code_scanner,
              label: 'Scan Another',
              outlined: true,
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
                    ? _cameraFailed
                          ? Container(
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
                                  const Gap(12),
                                  const Text(
                                    'Camera unavailable',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const Gap(12),
                                  BracuActionButton(
                                    onPressed: () => _ensureCameraPermission(
                                      openSettingsOnDeny: true,
                                    ),
                                    label: 'Retry Camera',
                                    outlined: true,
                                    foregroundColor: Colors.white,
                                  ),
                                ],
                              ),
                            )
                          : ReaderWidget(
                              codeFormat: Format.qrCode,
                              resolution: ResolutionPreset.high,
                              cropPercent: 0.85,
                              tryHarder: false,
                              tryRotate: true,
                              tryInverted: false,
                              tryDownscale: true,
                              maxNumberOfSymbols: 1,
                              showScannerOverlay: false,
                              showFlashlight: false,
                              showGallery: false,
                              showToggleCamera: false,
                              allowPinchZoom: false,
                              onControllerCreated: (_, error) {
                                if (error == null || !mounted) return;
                                setState(() => _cameraFailed = true);
                              },
                              onScan: (code) async {
                                if (scannedValue != null || _isSaving) return;
                                final value = code.text;
                                if (value == null || value.trim().isEmpty) {
                                  return;
                                }
                                final normalized = value.trim();
                                await _acceptScannedValue(normalized);
                              },
                            )
                    : Center(
                        child: BracuActionButton(
                          onPressed: () {
                            if (kIsWeb) {
                              setState(() => _cameraGranted = true);
                              return;
                            }
                            _ensureCameraPermission(openSettingsOnDeny: true);
                          },
                          label: 'Tap to enable camera',
                          outlined: true,
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
