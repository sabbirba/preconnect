export 'picker_types.dart' show SystemPickedImage;
export 'picker_stub.dart'
    if (dart.library.html) 'picker_web.dart'
    if (dart.library.io) 'picker_mobile.dart'
    show pickSystemImage;
