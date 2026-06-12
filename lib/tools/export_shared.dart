export 'platform_stub.dart'
    if (dart.library.html) 'export_web.dart'
    if (dart.library.io) 'platform_flutter.dart'
    show openImageInBrowser;
