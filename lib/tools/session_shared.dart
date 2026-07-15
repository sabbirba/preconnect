export 'platform_stub.dart'
    if (dart.library.js_interop) 'session_web.dart'
    if (dart.library.io) 'platform_stub.dart'
    show
        WebExtensionSessionFlow,
        WebExtensionSessionEvent,
        WebExtensionSessionEventKind;
