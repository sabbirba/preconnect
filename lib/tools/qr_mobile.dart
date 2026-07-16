import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:preconnect/tools/picker_mobile.dart';
import 'package:preconnect/tools/picker_utils.dart';

Future<String?> pickQrFromSystemImage() async {
  final picked = await pickSystemImage();
  if (picked == null) return null;
  final imagePath = await ensureReadableSystemImagePath(picked);
  if (imagePath.isEmpty) return null;
  final scanner = MobileScannerController();
  try {
    final capture = await scanner.analyzeImage(imagePath);
    if (capture == null || capture.barcodes.isEmpty) return null;
    final value = capture.barcodes.first.rawValue;
    if (value == null || value.trim().isEmpty) return null;
    return value;
  } finally {
    scanner.dispose();
  }
}
