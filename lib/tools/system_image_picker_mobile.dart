import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

import 'system_image_picker_types.dart';

Future<SystemPickedImage?> pickSystemImage() async {
  final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
  if (picked == null) return null;

  final bytes = await picked.readAsBytes();
  if (bytes.isEmpty) return null;
  return SystemPickedImage(
    bytes: Uint8List.fromList(bytes),
    name: picked.name,
    path: picked.path,
  );
}
