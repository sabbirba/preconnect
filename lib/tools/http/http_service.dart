import 'package:http/http.dart' as http;

import 'package:preconnect/tools/native_bridge/native_bridge.dart';

import 'http_client.dart';

class HttpService {
  static final http.Client client = createHttpClient();

  static bool get hasNativeBridge => NativeBridge.isSupported;

  static String? nativeBackendName() => NativeBridge.tryBackendName();
}
