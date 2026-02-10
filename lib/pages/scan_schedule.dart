import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:preconnect/pages/ui_kit.dart';

class ScanSchedulePage extends StatefulWidget {
  const ScanSchedulePage({super.key});

  @override
  State<ScanSchedulePage> createState() => _ScanSchedulePageState();
}

class _ScanSchedulePageState extends State<ScanSchedulePage> {
  final MobileScannerController _controller = MobileScannerController();
  String? scannedValue;
  bool _isPicking = false;

  bool get _supportsGalleryScan {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
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

  Future<void> _scanFromGallery() async {
    if (_isPicking) return;
    if (kIsWeb) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gallery scan is not supported on web')),
      );
      return;
    }
    setState(() => _isPicking = true);
    try {
      final picker = ImagePicker();
      final XFile? image = await picker.pickImage(source: ImageSource.gallery);
      if (image == null) return;

      final BarcodeCapture? capture =
          await _controller.analyzeImage(image.path);
      if (capture == null || capture.barcodes.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No QR code found in image')),
        );
        return;
      }

      final value = capture.barcodes.first.rawValue;
      if (value == null || value.trim().isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid QR code')),
        );
        return;
      }

      setState(() {
        scannedValue = value;
      });

      await _saveScannedValue(value);
      _controller.stop();
    } finally {
      if (mounted) {
        setState(() => _isPicking = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return BracuPageScaffold(
      title: 'Scan Schedule',
      subtitle: 'Import From QR',
      icon: Icons.qr_code_scanner,
      body: RefreshIndicator(
        onRefresh: _handleRefresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
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
                        child: MobileScanner(
                          controller: _controller,
                          onDetect: (capture) async {
                            final barcode = capture.barcodes.first;
                            if (barcode.rawValue != null) {
                              final value = barcode.rawValue!;
                              setState(() {
                                scannedValue = value;
                              });

                              await _saveScannedValue(value);
                              _controller.stop();
                            }
                          },
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (_supportsGalleryScan) ...[
                    InkWell(
                      onTap: _scanFromGallery,
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
                                Icons.photo_library_outlined,
                                color: BracuPalette.primary,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Text(
                                'Scan from Gallery',
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
                  ],
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
    );
  }
}
