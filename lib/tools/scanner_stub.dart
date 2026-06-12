import 'package:flutter/material.dart';

class MobileScannerController {
  MobileScannerController({bool autoStart = true});

  final MobileScannerControllerValue value = MobileScannerControllerValue();

  Future<void> start() async {}

  Future<void> stop() async {}

  void dispose() {}

  Future<BarcodeCapture?> analyzeImage(String path) async => null;
}

class MobileScannerControllerValue {
  bool get isRunning => false;
}

class MobileScanner extends StatelessWidget {
  const MobileScanner({
    super.key,
    required this.controller,
    this.errorBuilder,
    this.onDetect,
  });

  final MobileScannerController controller;
  final Widget Function(BuildContext, MobileScannerException)? errorBuilder;
  final void Function(BarcodeCapture)? onDetect;

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

class MobileScannerErrorCode {
  const MobileScannerErrorCode._(this.message);

  final String message;

  static const permissionDenied = MobileScannerErrorCode._(
    'Camera permission denied',
  );
}

class MobileScannerException implements Exception {
  const MobileScannerException({required this.errorCode, this.errorDetails});

  final MobileScannerErrorCode errorCode;
  final MobileScannerErrorDetails? errorDetails;
}

class MobileScannerErrorDetails {
  const MobileScannerErrorDetails({this.message});

  final String? message;
}

class BarcodeCapture {
  const BarcodeCapture({this.barcodes = const <Barcode>[]});

  final List<Barcode> barcodes;
}

class Barcode {
  const Barcode({this.rawValue});

  final String? rawValue;
}
