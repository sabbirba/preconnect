import 'package:flutter_zxing/flutter_zxing.dart';
import 'package:preconnect/tools/picker_mobile.dart';
import 'package:preconnect/tools/picker_utils.dart';

Future<String?> pickQrFromSystemImage() async {
  final picked = await pickSystemImage();
  if (picked == null) return null;
  final imagePath = await ensureReadableSystemImagePath(picked);
  if (imagePath.isEmpty) return null;
  final result = await zx.readBarcodeImagePathString(
    imagePath,
    DecodeParams(
      format: Format.qrCode,
      tryHarder: true,
      tryRotate: true,
      tryInverted: true,
      tryDownscale: true,
      maxNumberOfSymbols: 1,
    ),
  );
  final value = result.text?.trim();
  return result.isValid && value?.isNotEmpty == true ? value : null;
}
