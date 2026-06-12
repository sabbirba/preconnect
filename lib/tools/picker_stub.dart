import 'picker_types.dart';

Future<SystemPickedImage?> pickSystemImage() async {
  throw UnsupportedError(
    'System image picking is not supported on this platform.',
  );
}
