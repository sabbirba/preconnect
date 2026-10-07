import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:preconnect/tools/picker_mobile.dart';
import 'package:preconnect/tools/picker_utils.dart';

Future<String?> pickQrFromSystemImage() async {
  final picked = await pickSystemImage();
  if (picked == null) return null;
  final imagePath = await ensureReadableSystemImagePath(picked);
  if (imagePath.isEmpty) return null;
  final capture = await MobileScannerPlatform.instance.analyzeImage(
    imagePath,
    formats: const [BarcodeFormat.qrCode],
  );
  final value = capture?.barcodes.firstOrNull?.rawValue?.trim();
  return value != null && value.isNotEmpty ? value : null;
}
