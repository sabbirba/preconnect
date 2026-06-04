export 'web_platform_stub.dart'
    if (dart.library.html) 'web_page_title_web.dart'
    if (dart.library.io) 'web_platform_flutter.dart'
    show normalizeWebPageTitle, setWebPageTitle;
