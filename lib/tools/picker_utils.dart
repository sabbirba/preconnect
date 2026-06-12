import 'dart:io';

import 'package:preconnect/tools/picker_shared.dart';

Future<String> ensureReadableSystemImagePath(SystemPickedImage file) async {
  final path = file.path?.trim() ?? '';
  if (path.isNotEmpty && File(path).existsSync()) {
    return path;
  }
  try {
    final bytes = file.bytes;
    if (bytes.isEmpty) return path;
    final ext = file.name.contains('.') ? file.name.split('.').last.trim() : '';
    final safeExt = ext.isEmpty ? 'png' : ext;
    final tempFile = File(
      '${Directory.systemTemp.path}/preconnect_scan_${DateTime.now().millisecondsSinceEpoch}.$safeExt',
    );
    await tempFile.writeAsBytes(bytes, flush: true);
    return tempFile.path;
  } catch (_) {
    return path;
  }
}
