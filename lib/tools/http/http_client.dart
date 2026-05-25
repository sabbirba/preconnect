export 'http_stub.dart'
    if (dart.library.js_interop) 'http_web.dart'
    if (dart.library.io) 'http_native.dart';
