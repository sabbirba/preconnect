export 'web_platform_stub.dart'
    if (dart.library.html) 'web_extension_session_flow_web.dart'
    if (dart.library.io) 'web_platform_flutter.dart'
    show
        WebExtensionSessionFlow,
        WebExtensionSessionEvent,
        WebExtensionSessionEventKind;
