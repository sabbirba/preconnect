export 'web_platform_stub.dart'
    if (dart.library.html) 'web_qr_image_picker_web.dart'
    if (dart.library.io) 'web_platform_flutter.dart'
    show pickQrFromSystemImage;
