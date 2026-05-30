export 'web_platform_stub.dart'
    if (dart.library.html) 'web_image_export_web.dart'
    if (dart.library.ui) 'web_platform_flutter.dart'
    show openImageInBrowser;
