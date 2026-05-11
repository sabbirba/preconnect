export 'system_image_picker_types.dart' show SystemPickedImage;
export 'system_image_picker_stub.dart'
    if (dart.library.html) 'system_image_picker_web.dart'
    if (dart.library.io) 'system_image_picker_mobile.dart'
    show pickSystemImage;
