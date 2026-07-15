export 'platform_stub.dart'
    if (dart.library.js_interop) 'login_web.dart'
    if (dart.library.io) 'platform_stub.dart'
    show
        WebExtensionLoginFlow,
        WebExtensionLoginState,
        WebExtensionLoginStateKind;
