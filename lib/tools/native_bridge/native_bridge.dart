export 'native_bridge_stub.dart'
    if (dart.library.io) 'native_bridge_io.dart'
    if (dart.library.js_interop) 'native_bridge_web.dart';
