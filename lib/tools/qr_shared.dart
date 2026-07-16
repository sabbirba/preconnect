export 'qr_stub.dart'
    if (dart.library.js_interop) 'qr_web.dart'
    if (dart.library.io) 'qr_mobile.dart'
    show pickQrFromSystemImage;
