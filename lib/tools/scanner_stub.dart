import 'package:flutter/material.dart';

class Format {
  static const int qrCode = 8192;
}

class Code {
  const Code({this.text});

  final String? text;
}

enum ResolutionPreset { high }

class ReaderWidget extends StatelessWidget {
  const ReaderWidget({
    super.key,
    this.codeFormat = Format.qrCode,
    this.resolution = ResolutionPreset.high,
    this.cropPercent = 0.85,
    this.tryHarder = false,
    this.tryRotate = true,
    this.tryInverted = false,
    this.tryDownscale = false,
    this.maxNumberOfSymbols = 1,
    this.showScannerOverlay = false,
    this.showFlashlight = false,
    this.showGallery = false,
    this.showToggleCamera = false,
    this.allowPinchZoom = false,
    this.onControllerCreated,
    this.onScan,
  });

  final int codeFormat;
  final ResolutionPreset resolution;
  final double cropPercent;
  final bool tryHarder;
  final bool tryRotate;
  final bool tryInverted;
  final bool tryDownscale;
  final int maxNumberOfSymbols;
  final bool showScannerOverlay;
  final bool showFlashlight;
  final bool showGallery;
  final bool showToggleCamera;
  final bool allowPinchZoom;
  final void Function(Object?, Exception?)? onControllerCreated;
  final void Function(Code)? onScan;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(16),
      child: const Text(
        'Camera scanning is unavailable in the extension.',
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.white),
      ),
    );
  }
}
