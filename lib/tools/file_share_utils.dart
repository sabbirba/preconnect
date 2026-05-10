import 'dart:typed_data';

import 'package:preconnect/tools/app_paths.dart';
import 'package:share_plus/share_plus.dart';

Future<void> shareTemporaryBytesFile({
  required String fileName,
  required Uint8List bytes,
  required String text,
}) async {
  final file = await AppPaths.writeTemporaryFile(
    fileName: fileName,
    bytes: bytes,
  );
  await SharePlus.instance.share(
    ShareParams(files: [XFile(file.path)], text: text),
  );
}
