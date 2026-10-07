import 'package:flutter/material.dart';

enum BarcodeFormat { qrCode }

enum DetectionSpeed { normal, noDuplicates, unrestricted }

class Barcode {
  const Barcode({this.rawValue});

  final String? rawValue;
}

class BarcodeCapture {
  const BarcodeCapture({this.barcodes = const []});

  final List<Barcode> barcodes;
}

class MobileScannerException implements Exception {}

class MobileScannerPlatform {
  static final MobileScannerPlatform instance = MobileScannerPlatform();

  Future<BarcodeCapture?> analyzeImage(
    String path, {
    List<BarcodeFormat> formats = const [],
  }) async => null;
}

class MobileScannerController {
  MobileScannerController({
    List<BarcodeFormat>? formats,
    DetectionSpeed? detectionSpeed,
    Size? cameraResolution,
    bool? autoStart,
    bool? returnImage,
  });

  Future<void> start() async {}
  Future<void> stop() async {}
  Future<BarcodeCapture?> analyzeImage(
    String path, {
    List<BarcodeFormat> formats = const [],
  }) async => null;
  void dispose() {}
}

class MobileScanner extends StatelessWidget {
  const MobileScanner({
    super.key,
    this.controller,
    this.onDetect,
    this.errorBuilder,
    this.fit,
  });

  final MobileScannerController? controller;
  final void Function(BarcodeCapture)? onDetect;
  final Widget Function(BuildContext, dynamic)? errorBuilder;
  final BoxFit? fit;

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
