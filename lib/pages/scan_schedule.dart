import 'package:material_ui/material_ui.dart';
import 'package:gap/gap.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:file_selector/file_selector.dart' show XTypeGroup, openFile;
import 'package:permission_handler/permission_handler.dart';
import 'package:preconnect/api/friend_store.dart';
import 'package:preconnect/model/friend_schedule.dart';
import 'package:preconnect/pages/friend_sections/schedule_list.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/token_storage.dart';
import 'package:mobile_scanner/mobile_scanner.dart'
    if (dart.library.js_interop) 'package:preconnect/tools/scanner_stub.dart';
import 'package:preconnect/tools/clipboard_stub.dart'
    if (dart.library.js_interop) 'package:preconnect/tools/clipboard_web.dart';

class ScanSchedulePage extends StatefulWidget {
  const ScanSchedulePage({
    super.key,
    required this.onCompleted,
    required this.onSaved,
  });

  final VoidCallback onCompleted;
  final VoidCallback onSaved;

  @override
  State<ScanSchedulePage> createState() => _ScanSchedulePageState();
}

class _ScanSchedulePageState extends State<ScanSchedulePage> {
  final FriendScheduleStore _store = FriendScheduleStore();
  late final MobileScannerController _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.unrestricted,
    cameraResolution: const Size(1920, 1080),
    autoZoom: true,
  );
  String? scannedValue;
  Map<String, FriendSchedule> _added = const {};
  bool? _cameraGranted;
  bool _cameraFailed = false;
  bool _isEnablingCamera = false;
  bool _isSaving = false;

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
      final added = await _store.importPayload(value);
      if (!mounted) return;
      setState(() {
        scannedValue = value;
        _added = added;
      });
      widget.onSaved();
      _controller.stop();
    } on FormatException {
      if (!mounted) return;
      showAppSnackBar(context, 'Invalid friend schedule code');
    } catch (_) {
      if (!mounted) return;
      showAppSnackBar(context, 'Could not save friend schedule');
    } finally {
      _isSaving = false;
    }
  }

  Future<void> _importFile() async {
    final picked = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Friends Export',
          extensions: ['txt'],
          mimeTypes: ['text/plain'],
          uniformTypeIdentifiers: ['public.plain-text'],
        ),
      ],
    );
    if (picked == null) return;
    final String text;
    try {
      text = await picked.readAsString();
    } catch (_) {
      if (!mounted) return;
      showAppSnackBar(context, 'Could not read the file');
      return;
    }
    await _acceptScannedValue(text);
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
    _controller.start();
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
            AppCard(
              child: SizedBox(
                width: double.infinity,
                child: AppActionButton(
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
      return FriendsAddedView(
        added: _added,
        onDone: widget.onCompleted,
        onScanAnother: _restartScanner,
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
                                  AppActionButton(
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
                          : MobileScanner(
                              controller: _controller,
                              fit: BoxFit.cover,
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
                                      AppActionButton(
                                        onPressed: () =>
                                            _ensureCameraPermission(
                                              openSettingsOnDeny: true,
                                            ),
                                        label: 'Retry Camera',
                                        outlined: true,
                                        foregroundColor: Colors.white,
                                      ),
                                    ],
                                  ),
                                );
                              },
                              onDetect: (capture) async {
                                if (scannedValue != null || _isSaving) return;
                                final barcode = capture.barcodes.firstOrNull;
                                final value = barcode?.rawValue?.trim();
                                if (value == null || value.isEmpty) {
                                  return;
                                }
                                await _acceptScannedValue(value);
                              },
                            )
                    : Center(
                        child: AppActionButton(
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
            Row(
              children: [
                Expanded(
                  child: AppActionButton(
                    onPressed: _pasteCode,
                    icon: Icons.paste_rounded,
                    label: 'Paste Code',
                    outlined: true,
                  ),
                ),
                const Gap(12),
                Expanded(
                  child: AppActionButton(
                    onPressed: _importFile,
                    icon: Icons.file_open_outlined,
                    label: 'Import File',
                    outlined: true,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class FriendsAddedView extends StatelessWidget {
  const FriendsAddedView({
    super.key,
    required this.added,
    required this.onDone,
    this.onScanAnother,
  });

  final Map<String, FriendSchedule> added;
  final VoidCallback onDone;
  final VoidCallback? onScanAnother;

  @override
  Widget build(BuildContext context) {
    final onScanAnother = this.onScanAnother;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Gap(8),
          const Icon(
            Icons.check_circle_rounded,
            size: 56,
            color: AppPalette.accent,
          ),
          const Gap(12),
          Text(
            added.length > 1 ? 'Schedules Added' : 'Schedule Added',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const Gap(16),
          for (final entry in added.entries)
            FriendScheduleSection(
              item: FriendScheduleItem(encoded: entry.key, friend: entry.value),
              showActions: false,
            ),
          const Gap(8),
          AppActionButton(
            onPressed: onDone,
            icon: Icons.check_circle_rounded,
            label: 'Done',
            outlined: false,
            backgroundColor: AppPalette.accent,
            foregroundColor: Colors.white,
          ),
          if (onScanAnother != null) ...[
            const Gap(12),
            AppActionButton(
              onPressed: onScanAnother,
              icon: Icons.qr_code_scanner,
              label: 'Scan Another',
              outlined: true,
            ),
          ],
        ],
      ),
    );
  }
}
