import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';

import 'system_image_picker_types.dart';

Future<SystemPickedImage?> pickSystemImage() async {
  final XFile? picked = await openFile(
    acceptedTypeGroups: [
      XTypeGroup(
        label: 'Images',
        extensions: ['png', 'jpg', 'jpeg', 'gif', 'webp', 'heic'],
      ),
    ],
  );
  if (picked == null) return null;

  final bytes = await picked.readAsBytes();
  if (bytes.isEmpty) return null;

  return SystemPickedImage(bytes: Uint8List.fromList(bytes), name: picked.name);
}
