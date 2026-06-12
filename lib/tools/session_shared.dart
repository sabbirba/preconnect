export 'platform_stub.dart'
    if (dart.library.html) 'session_web.dart'
    if (dart.library.io) 'platform_flutter.dart'
    show
        WebExtensionSessionFlow,
        WebExtensionSessionEvent,
        WebExtensionSessionEventKind;
