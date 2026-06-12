export 'platform_stub.dart'
    if (dart.library.html) 'title_web.dart'
    if (dart.library.io) 'platform_flutter.dart'
    show normalizeWebPageTitle, setWebPageTitle;
