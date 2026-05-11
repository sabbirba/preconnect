import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import 'system_image_picker_types.dart';

Future<SystemPickedImage?> pickSystemImage() async {
  final picked = await FilePicker.pickFiles(
    type: FileType.image,
    allowMultiple: false,
    withData: true,
  );
  if (picked == null || picked.files.isEmpty) return null;

  final file = picked.files.first;
  final bytes = file.bytes;
  if (bytes == null || bytes.isEmpty) return null;

  return SystemPickedImage(bytes: Uint8List.fromList(bytes), name: file.name);
}
